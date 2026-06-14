# SRE Technical Challenge — AWS Serverless Architecture

Implementación de una arquitectura serverless en AWS usando Terraform, con caché Redis, almacenamiento S3 y API REST.

**Owner:** sresundevs03@gmail.com  
**Región:** us-east-1 | **Entorno:** qa

---

## Arquitectura

```
Cliente HTTP
    │
    ▼
┌─────────────────────────────────────────┐
│  API Gateway (HTTP API)                 │
│  POST /process  │  throttle: 5 rps      │
└─────────────────┬───────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────┐
│  Lambda: sre-challenge-qa-processor     │
│  Python 3.11 │ 256 MB │ timeout: 30s   │
│  VPC: subnets privadas                  │
└────────┬────────────────────┬───────────┘
         │                    │
         ▼                    ▼
┌─────────────────┐  ┌────────────────────┐
│  ElastiCache    │  │  S3 Bucket         │
│  Redis 7.1      │  │  sre-challenge-    │
│  cache.t3.micro │  │  qa-results        │
│  TTL: 60s       │  │  results/<date>/   │
│  HIT → return   │  │  <id>.json         │
│  MISS → store   │  │                    │
└─────────────────┘  └────────────────────┘

Flujo cache:
  HIT  → Redis devuelve valor  → X-Cache: HIT
  MISS → procesa → S3 → Redis  → X-Cache: MISS
```

---

## Servicios desplegados

| Servicio | Recurso | Costo |
|---|---|---|
| VPC | 2 subnets públicas + 2 privadas, IGW, NAT GW, VPC Endpoint S3 | NAT GW: $0.045/hr |
| API Gateway | HTTP API, POST /process, throttling, CORS, access logs | Free Tier |
| Lambda | Python 3.11, dentro de VPC, manejo de errores | Free Tier |
| ElastiCache | Redis 7.1, cache.t3.micro, single-node | Free Tier (primer año) |
| S3 | Block Public Access x4, versionado, AES-256 | Free Tier |
| CloudWatch | Log groups con retención 7 días | Free Tier |
| SNS + EventBridge | Alertas de expiración diarias | Free Tier |

---

## Prerequisitos

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.7
- [Python](https://www.python.org/downloads/) >= 3.11
- [AWS CLI](https://aws.amazon.com/cli/) configurado con perfil `sre-challenge`
- Perfil AWS con permisos suficientes (AdministratorAccess para este challenge)

Configurar perfil AWS:
```bash
aws configure --profile sre-challenge
# AWS Access Key ID:     AKIA...
# AWS Secret Access Key: ...
# Default region:        us-east-1
# Default output format: json
```

---

## Deploy

```powershell
# Clonar repo
git clone https://github.com/sresundevs03/sre-challenge.git
cd sre-challenge

# Copiar y configurar variables
Copy-Item terraform\terraform.tfvars.example terraform\terraform.tfvars
# Editar terraform.tfvars con tus valores

# Desplegar
.\scripts\deploy.ps1

# Validar
.\scripts\validate.ps1
```

Deploy manual paso a paso:
```powershell
cd terraform
terraform init
terraform validate
terraform plan
terraform apply
```

---

## Uso del API

**Endpoint:** `https://or9vc0o50j.execute-api.us-east-1.amazonaws.com/process`

### Cache MISS (primera llamada)
```bash
curl -X POST https://or9vc0o50j.execute-api.us-east-1.amazonaws.com/process \
  -H "Content-Type: application/json" \
  -d '{"user": "demo", "action": "process", "data": "hello world"}' \
  -D -
```

Respuesta esperada:
```
HTTP/1.1 200 OK
X-Cache: MISS
X-Request-Id: 4ac54c31-8661-4a15-bd47-2afd49f76bfa

{
  "id": "4ac54c31-8661-4a15-bd47-2afd49f76bfa",
  "timestamp": "2026-06-14T01:28:35.296970Z",
  "cache_key": "745709780c...",
  "input": {"user": "demo", "action": "process", "data": "hello world"},
  "processed": true,
  "s3_key": "results/2026-06-14/4ac54c31-....json"
}
```

### Cache HIT (misma llamada, dentro de 60 segundos)
```bash
curl -X POST https://or9vc0o50j.execute-api.us-east-1.amazonaws.com/process \
  -H "Content-Type: application/json" \
  -d '{"user": "demo", "action": "process", "data": "hello world"}' \
  -D -
```

Respuesta esperada:
```
HTTP/1.1 200 OK
X-Cache: HIT

{ ... mismo objeto cacheado ... }
```

### Verificar objeto en S3
```bash
aws s3 ls s3://sre-challenge-qa-results/results/ --recursive --profile sre-challenge
```

---

## Destrucción de recursos

> Ejecutar antes del **2026-06-23** para evitar cargos del NAT Gateway.

```powershell
.\scripts\destroy.ps1
```

O manualmente:
```powershell
# 1. Vaciar bucket S3
aws s3 rm s3://sre-challenge-qa-results --recursive --profile sre-challenge

# 2. Destruir infraestructura
cd terraform
terraform destroy --auto-approve
```

---

## Decisiones de diseño

Ver [docs/DECISIONS.md](docs/DECISIONS.md) para el detalle de cada decisión arquitectónica.

Ver [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) para la arquitectura técnica completa.
