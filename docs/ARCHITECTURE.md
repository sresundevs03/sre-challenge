# Arquitectura Técnica — SRE Challenge

## Diagrama de red

```
┌──────────────────────────── VPC: 10.0.0.0/16 ─────────────────────────────┐
│                                                                             │
│  ┌─── AZ us-east-1a ──────────┐  ┌─── AZ us-east-1b ──────────┐          │
│  │  Public: 10.0.1.0/24       │  │  Public: 10.0.2.0/24        │          │
│  │  ┌──────────────────────┐  │  │                             │          │
│  │  │    NAT Gateway       │  │  │                             │          │
│  │  │    EIP: dinámico     │  │  │                             │          │
│  │  └──────────────────────┘  │  │                             │          │
│  │                            │  │                             │          │
│  │  Private: 10.0.11.0/24    │  │  Private: 10.0.12.0/24     │          │
│  │  ┌──────────────────────┐  │  │  ┌──────────────────────┐  │          │
│  │  │  Lambda processor    │  │  │  │  (standby subnet)    │  │          │
│  │  │  SG: sg-lambda       │  │  │  │                      │  │          │
│  │  └─────────┬────────────┘  │  │  └──────────────────────┘  │          │
│  │            │ :6379         │  │                             │          │
│  │  ┌─────────▼────────────┐  │  │                             │          │
│  │  │  ElastiCache Redis   │  │  │                             │          │
│  │  │  SG: sg-redis        │  │  │                             │          │
│  │  └──────────────────────┘  │  │                             │          │
│  └────────────────────────────┘  └─────────────────────────────┘          │
│                                                                             │
│  Internet Gateway ──► Route Table Public ──► NAT GW ──► Route Table Private│
│  VPC Endpoint S3 (Gateway) ──► Route Table Private (sin salir a internet)  │
└─────────────────────────────────────────────────────────────────────────────┘
         │
         │ HTTPS
         ▼
    Internet → API Gateway → Lambda (en VPC privada)
```

---

## Flujo de datos detallado

```
1. Cliente envía POST /process con JSON body

2. API Gateway (HTTP API)
   - Valida que sea POST /process
   - Aplica throttling: burst=10, rate=5 rps
   - Agrega headers CORS
   - Escribe access log en CloudWatch
   - Invoca Lambda processor

3. Lambda processor (Python 3.11)
   a. Parsea body JSON
   b. Genera cache_key = SHA256(json.dumps(body, sort_keys=True))
   c. Conecta a Redis en subnet privada
   d. Busca cache_key en Redis

   CACHE HIT:
     → Retorna valor cacheado
     → Header: X-Cache: HIT
     → No toca S3

   CACHE MISS:
     → Genera request_id = UUID4
     → Construye resultado con timestamp
     → PUT en S3: results/<YYYY-MM-DD>/<uuid>.json
       (tráfico va por VPC Endpoint Gateway — no sale a internet)
     → SET en Redis: cache_key → JSON, TTL=60s
     → Header: X-Cache: MISS, X-Request-Id: <uuid>

4. Lambda retorna respuesta → API Gateway → Cliente
```

---

## Componentes

### VPC (`modules/vpc`)
- **CIDR:** 10.0.0.0/16
- **Subnets públicas:** 10.0.1.0/24 (us-east-1a), 10.0.2.0/24 (us-east-1b)
- **Subnets privadas:** 10.0.11.0/24 (us-east-1a), 10.0.12.0/24 (us-east-1b)
- **Internet Gateway:** para subnets públicas
- **NAT Gateway:** una instancia en us-east-1a (costo optimizado para QA)
- **VPC Endpoint S3 (Gateway):** tráfico Lambda→S3 permanece en red AWS, sin NAT

### Security Groups (`modules/security_groups`)

| SG | Ingress | Egress |
|---|---|---|
| `sg-lambda` | ninguno | Redis:6379, HTTPS:443, DNS:53 |
| `sg-redis` | Lambda:6379 | ninguno |

### API Gateway (`modules/api_gateway`)
- **Tipo:** HTTP API (payload format 2.0)
- **Ruta:** POST /process
- **Throttling:** burst=10, rate=5 rps
- **CORS:** allow-origins=*, allow-methods=POST/OPTIONS
- **Access logs:** CloudWatch JSON format, retención 7 días

### Lambda (`modules/lambda`)
- **Función processor:** Python 3.11, 256 MB, timeout 30s, en VPC privada
- **Función expiry-checker:** Python 3.11, 128 MB, timeout 60s, sin VPC (llama SNS)
- **Build:** pip install redis en lambda/package/, empaquetado como zip por Terraform

### ElastiCache (`modules/elasticache`)
- **Engine:** Redis 7.1
- **Node type:** cache.t3.micro (Free Tier primer año)
- **Nodos:** 1 (single-node, sin HA por diseño QA)
- **Puerto:** 6379
- **Acceso:** solo desde sg-lambda

### S3 (`modules/s3`)
- **Bucket:** sre-challenge-qa-results
- **Block Public Access:** las 4 opciones habilitadas
- **Versionado:** habilitado
- **Encriptación:** AES-256 (SSE-S3)
- **Lifecycle:** objetos en results/ expiran a 30 días, versiones a 7 días
- **Prefijo de objetos:** `results/<YYYY-MM-DD>/<uuid>.json`

### IAM (`modules/iam`)
- **Role processor:** `AWSLambdaVPCAccessExecutionRole` + política custom S3 PutObject/GetObject en `results/*`
- **Role expiry-checker:** `AWSLambdaBasicExecutionRole` + SNS:Publish

### CloudWatch
- `/aws/lambda/sre-challenge-qa-processor` — retención 7 días
- `/aws/lambda/sre-challenge-qa-expiry-checker` — retención 7 días
- `/aws/apigateway/sre-challenge-qa-api` — access logs, retención 7 días

### SNS + EventBridge
- **SNS topic:** `sre-challenge-qa-expiry-alerts` — email a sresundevs03@gmail.com
- **EventBridge rule:** `rate(1 day)` → invoca `expiry-checker` Lambda
- **Alerta:** cuando quedan ≤3 días para ExpiryDate (2026-06-23)

---

## Tagging

Todos los recursos tienen estos tags vía `provider default_tags`:

```hcl
Project     = "sre-challenge"
Environment = "qa"
Owner       = "sresundevs03@gmail.com"
ManagedBy   = "terraform"
ExpiryDate  = "2026-06-23"
Repository  = "github.com/sresundevs03/sre-challenge"
```

---

## Análisis de costos

| Recurso | Precio | Estimado 10 días |
|---|---|---|
| NAT Gateway | $0.045/hr | **$10.80** |
| ElastiCache t3.micro | Free Tier (750 hrs/mes) | $0.00 |
| Lambda | Free Tier (1M req/mes) | $0.00 |
| API Gateway HTTP | Free Tier (1M req/mes) | $0.00 |
| S3 | Free Tier (5 GB) | $0.00 |
| CloudWatch Logs | Free Tier (5 GB) | $0.00 |
| **TOTAL** | | **~$10.80** |

Budget configurado: alerta a $5 y $8 USD.
