# Justificación Técnica — SRE Challenge

**Proyecto:** AWS Serverless Architecture con caché Redis  
**Cuenta AWS:** 779035456288 | **Región:** us-east-1 | **Entorno:** qa  
**Owner:** sresundevs03@gmail.com  
**Infraestructura válida hasta:** 2026-06-23

---

## Índice

1. [Qué construimos](#1-qué-construimos)
2. [Decisiones de infraestructura](#2-decisiones-de-infraestructura)
3. [Decisiones de red y seguridad](#3-decisiones-de-red-y-seguridad)
4. [Decisiones de aplicación (Lambda)](#4-decisiones-de-aplicación-lambda)
5. [Decisiones de caché (ElastiCache Redis)](#5-decisiones-de-caché-elasticache-redis)
6. [Decisiones de almacenamiento (S3)](#6-decisiones-de-almacenamiento-s3)
7. [Decisiones de API (API Gateway)](#7-decisiones-de-api-api-gateway)
8. [Decisiones de identidad y acceso (IAM)](#8-decisiones-de-identidad-y-acceso-iam)
9. [Decisiones de observabilidad y alertas](#9-decisiones-de-observabilidad-y-alertas)
10. [Decisiones de Terraform (IaC)](#10-decisiones-de-terraform-iac)
11. [Decisiones de costos](#11-decisiones-de-costos)
12. [Trade-offs aceptados](#12-trade-offs-aceptados)

---

## 1. Qué construimos

Se desplegó una arquitectura serverless completa en AWS, gestionada 100% con Terraform, que implementa un flujo de procesamiento con caché:

```
Internet
   │ HTTPS POST /process
   ▼
API Gateway (HTTP API)
   │ invocación síncrona (AWS Proxy)
   ▼
Lambda: processor (Python 3.11, VPC privada)
   │
   ├── [cache HIT]  ──► Redis (ElastiCache) ──► respuesta inmediata  X-Cache: HIT
   │
   └── [cache MISS] ──► genera UUID + timestamp
                         ├── S3 PUT results/<fecha>/<uuid>.json   (via VPC Endpoint)
                         └── Redis SET cache_key TTL=60s
                                         ──► respuesta             X-Cache: MISS
```

### Componentes desplegados

| Módulo Terraform | Recurso AWS | Propósito |
|---|---|---|
| `modules/vpc` | VPC, subnets, IGW, NAT GW, VPC Endpoint S3 | Red aislada, tráfico privado |
| `modules/security_groups` | 2 SGs + 5 reglas | Control de acceso entre Lambda y Redis |
| `modules/s3` | S3 Bucket + configuración | Almacenamiento persistente de resultados |
| `modules/iam` | 2 roles + 4 políticas | Least privilege para Lambda |
| `modules/elasticache` | Redis 7.1 cluster | Caché en memoria, TTL 60s |
| `modules/lambda` | 2 funciones Lambda | Procesamiento + alertas de expiración |
| `modules/api_gateway` | HTTP API + ruta + stage | Punto de entrada público HTTPS |
| `main.tf` (root) | SNS, EventBridge, bucket policy | Alertas y control de acceso S3 |

**Total de recursos Terraform gestionados:** 54 recursos  
**Estado del último `terraform plan`:** 0 changes (infraestructura en sync)  
**Validación:** 15/15 checks OK (`scripts/validate.ps1`)

---

## 2. Decisiones de infraestructura

### 2.1 Terraform modular vs monolítico

**Decisión:** estructura modular con 6 módulos independientes.

Cada módulo encapsula un dominio de infraestructura (red, seguridad, cómputo, almacenamiento). Esto permite:
- **Reutilización:** los módulos aceptan variables y pueden usarse en otros entornos (staging, prod) sin cambiar código
- **Visibilidad:** `terraform plan` muestra cambios agrupados por módulo, lo que facilita la revisión
- **Aislamiento de blast radius:** un error en el módulo `lambda` no puede corromper el estado del módulo `vpc`

La alternativa (todo en un solo `main.tf`) se descartó porque con 54 recursos se vuelve imposible de mantener.

### 2.2 Prefijo de nombres: `{project}-{env}`

**Decisión:** todos los recursos usan el prefijo `sre-challenge-qa-` como `local.prefix`.

El patrón `{project}-{environment}` permite tener múltiples entornos (`qa`, `staging`, `prod`) en la misma cuenta sin colisión de nombres. Los tags adicionales (`Project`, `Environment`, `ExpiryDate`) permiten filtrar y agrupar costos en AWS Cost Explorer.

### 2.3 `default_tags` en el provider de AWS

**Decisión:** todos los tags se definen una sola vez en el bloque `provider`, no en cada recurso.

```hcl
default_tags {
  tags = {
    Project     = var.project_name
    Environment = var.environment
    Owner       = var.owner_email
    ManagedBy   = "terraform"
    ExpiryDate  = var.expiry_date
    Repository  = "github.com/sresundevs03/sre-challenge"
  }
}
```

Esto garantiza que **todos** los recursos (incluso los creados por módulos anidados) reciban los mismos tags sin posibilidad de omisión. Es el patrón recomendado por HashiCorp desde Terraform AWS Provider v3.38.

---

## 3. Decisiones de red y seguridad

### 3.1 VPC dedicada con subnets públicas y privadas

**Decisión:** VPC `10.0.0.0/16` con 2 subnets públicas y 2 privadas en dos AZs.

La Lambda y ElastiCache viven en **subnets privadas** — no tienen IP pública, no son accesibles desde internet. El único ingreso es via API Gateway (managed service de AWS, fuera de la VPC).

Las subnets públicas alojan únicamente el NAT Gateway (para que Lambda pueda hacer llamadas salientes a AWS APIs como SNS y S3 via endpoint).

Separar en dos AZs (`us-east-1a`, `us-east-1b`) prepara la infraestructura para HA sin costo adicional en subnets.

### 3.2 Un solo NAT Gateway en lugar de uno por AZ

**Decisión:** NAT Gateway único en `us-east-1a`.

Un NAT Gateway por AZ cuesta ~$0.045/hr cada uno. Con dos AZs activas serían ~$65/mes solo en NAT. Para un entorno QA con fecha de expiración en 10 días, el costo supera ampliamente el beneficio de la HA.

**Trade-off aceptado:** si `us-east-1a` falla, las Lambdas en `us-east-1b` no tienen salida a internet para SNS. Para producción, se usaría un NAT por AZ.

### 3.3 VPC Endpoint Gateway para S3

**Decisión:** endpoint tipo Gateway para que el tráfico Lambda→S3 no pase por el NAT Gateway.

Sin el endpoint, cada PUT/GET de Lambda a S3 pasa por el NAT Gateway con un costo de $0.045/GB de procesamiento. Con el endpoint tipo Gateway (sin costo adicional), el tráfico permanece en la red privada de AWS.

Adicionalmente, esto mejora la seguridad: los datos nunca salen a internet.

El endpoint se adjunta a la Route Table privada con una ruta específica para el prefijo de S3 en `us-east-1`.

### 3.4 Security Groups sin reglas inline (circular dependency fix)

**Decisión:** crear `aws_security_group` vacíos y agregar reglas con recursos `aws_security_group_rule` separados.

El problema: Lambda SG necesita una regla de egress hacia Redis SG, y Redis SG necesita una regla de ingress desde Lambda SG. Si se definen inline con `ingress`/`egress` en el mismo bloque del SG, Terraform detecta una dependencia circular porque cada SG referencia al otro antes de que exista.

Solución:
```hcl
resource "aws_security_group" "lambda" { ... }  # sin reglas
resource "aws_security_group" "redis"  { ... }  # sin reglas

resource "aws_security_group_rule" "lambda_egress_redis" {
  source_security_group_id = aws_security_group.redis.id  # ahora ya existe
}
resource "aws_security_group_rule" "redis_ingress_lambda" {
  source_security_group_id = aws_security_group.lambda.id  # ahora ya existe
}
```

Los SGs se crean primero (sin reglas), luego las reglas se agregan en un segundo paso donde ambos IDs ya están disponibles.

### 3.5 Reglas de egress de Lambda (mínimo necesario)

**Decisión:** Lambda solo tiene egress en los puertos estrictamente necesarios.

| Puerto | Protocolo | Destino | Razón |
|---|---|---|---|
| 6379 | TCP | Redis SG | Conexión a ElastiCache |
| 443 | TCP | 0.0.0.0/0 | HTTPS a AWS APIs (S3 via endpoint, SNS) |
| 53 | UDP | 0.0.0.0/0 | DNS resolution |
| 53 | TCP | 0.0.0.0/0 | DNS resolution (fallback TCP) |

No hay reglas de ingress en Lambda — API Gateway invoca Lambda directamente via IAM, no abre conexiones de red.

---

## 4. Decisiones de aplicación (Lambda)

### 4.1 Python 3.11 como runtime

**Decisión:** Python 3.11.

Python 3.11 tiene soporte hasta noviembre 2027 y es activamente mantenido por AWS en Lambda. Tiene `cold start` más bajo que Java/Go para funciones pequeñas, y la librería `redis-py` (única dependencia) está madura y bien documentada.

### 4.2 Cache key: SHA256(json.dumps(body, sort_keys=True))

**Decisión:** hash SHA256 del body JSON canonicalizado.

`sort_keys=True` garantiza que el orden de las claves no afecte el cache key:
```
{"b": 1, "a": 2}  →  mismo cache key que  {"a": 2, "b": 1}
```

SHA256 produce un string hexadecimal de 64 caracteres sin caracteres especiales, ideal como Redis key. La probabilidad de colisión es negligible (2^-256).

Alternativas descartadas:
- MD5: colisiones conocidas, desaconsejado para nuevos proyectos
- Body raw como key: claves largas, sensible al orden de campos

### 4.3 Dos funciones Lambda independientes

**Decisión:** una función para procesar requests (`processor`) y otra para verificar expiración (`expiry_checker`).

Las responsabilidades son fundamentalmente distintas:
- `processor`: dentro de VPC (necesita acceso a Redis), alta frecuencia, timeout 30s, 256 MB
- `expiry_checker`: sin VPC (solo necesita SNS, que es público), una vez al día, timeout 60s, 128 MB

Combinarlas en una sola función obligaría a poner la función en VPC (por Redis), lo que añadiría latencia de cold start innecesaria a la funcionalidad de alertas.

### 4.4 Lambda en VPC privada con timeout 30s

**Decisión:** timeout conservador de 30s para el processor.

El flujo más lento es MISS: conectar a Redis (2s timeout), PUT en S3 (~100ms dentro de VPC), SET en Redis (~1ms). El 30s cubre con amplitud cualquier degradación de Redis o S3 sin acumular cost por timeouts excesivos.

### 4.5 Packaging via null_resource + archive_file en Windows

**Decisión:** `null_resource` con `local-exec` PowerShell para `pip install`, luego `archive_file` para empaquetar.

En Windows, las alternativas comunes para Lambda packaging no funcionan bien:
- Docker build: requiere Docker instalado y configurado
- Lambda Layer: agrega complejidad por una sola dependencia (`redis==5.0.1`)
- ECR container image: overhead de registry para una función simple

El `null_resource` corre pip install en `lambda/package/` al detectar cambios en `requirements.txt` o en los archivos `.py`. `archive_file` toma ese directorio y genera el ZIP que Terraform sube a Lambda.

---

## 5. Decisiones de caché (ElastiCache Redis)

### 5.1 Redis 7.1 sobre Memcached

**Decisión:** Redis 7.1 (no Memcached).

Redis permite TTL por clave, estructuras de datos ricas, y persistencia opcional. Para este caso TTL=60s por entrada es el requisito central — Memcached lo soporta, pero Redis es más estándar en la industria y tiene mejor soporte en `redis-py`.

### 5.2 Single-node, sin cluster mode

**Decisión:** 1 nodo `cache.t3.micro`, sin réplica, sin cluster mode.

`cache.t3.micro` entra en Free Tier (750 horas/mes el primer año). El challenge pide demostrar caché HIT/MISS, no alta disponibilidad. Cluster mode con Multi-AZ multiplicaría el costo por 2-3x sin beneficio funcional para un entorno QA de 10 días.

### 5.3 Cluster ID de máximo 20 caracteres

**Decisión:** `cluster_id = "sre-qa-redis"` (12 caracteres).

AWS impone un límite de 20 caracteres para el cluster ID de ElastiCache. El nombre natural `sre-challenge-qa-redis` tiene 22 caracteres y falla con error de validación. Se resolvió usando una variable separada `cluster_name` con valor corto.

### 5.4 snapshot_retention_limit = 0

**Decisión:** sin backups automáticos de Redis.

Los snapshots de ElastiCache tienen costo adicional ($0.023/GB-mes). Para un entorno QA con expiración en 10 días y datos de caché por naturaleza efímeros (TTL=60s), los backups no tienen valor funcional.

---

## 6. Decisiones de almacenamiento (S3)

### 6.1 Block Public Access en las 4 configuraciones

**Decisión:** `block_public_acls`, `block_public_policy`, `ignore_public_acls`, `restrict_public_buckets` = true.

Los resultados procesados son datos internos. No hay ningún caso de uso que justifique acceso público. Las 4 flags bloquean tanto ACLs heredados como nuevas políticas públicas, y previenen que un error de configuración futuro exponga datos.

### 6.2 Prefijo `results/<YYYY-MM-DD>/<uuid>.json`

**Decisión:** estructura de prefijos jerárquica con fecha.

Agrupa los objetos por fecha, lo que facilita:
- Búsquedas por rango de fechas con `aws s3 ls --recursive`
- La regla de lifecycle (expirar objetos en `results/` a 30 días)
- Auditoría: dado un `uuid` de respuesta, se puede localizar el objeto exacto

### 6.3 Bucket policy con dos capas de control

**Decisión:** policy con tres statements (`AllowLambdaProcessorOnly`, `DenyAllOthers`, `DenyNonSSL`).

La política IAM del rol processor (identity-based policy) ya permite PutObject/GetObject. Pero una identity-based policy no impide que un usuario con `AdministratorAccess` acceda al mismo bucket. El resource-based bucket policy agrega una segunda capa:

- **AllowLambdaProcessorOnly:** permite explícitamente al rol de Lambda
- **DenyAllOthers:** deniega a cualquier principal cuyo ARN no sea el rol de Lambda. Un Deny explícito en bucket policy siempre gana sobre cualquier Allow de IAM identity-based policy
- **DenyNonSSL:** deniega cualquier tráfico HTTP (no HTTPS), independientemente del principal

**Por qué en `main.tf` y no en `modules/s3`:**  
El módulo IAM necesita `module.s3.bucket_arn` para crear la policy inline. Si el módulo S3 también necesitara `module.iam.processor_role_arn`, Terraform detectaría un ciclo: `module.s3 → module.iam → module.s3`. Para romper el ciclo, la bucket policy se define en root `main.tf` donde ambos outputs ya están disponibles sin dependencia circular.

### 6.4 Lifecycle: objetos expiran a 30 días, versiones a 7 días

**Decisión:** retención limitada para controlar costos post-expiración del challenge.

Aunque la infraestructura se destruirá el 2026-06-23, la lifecycle rule previene acumulación de objetos en caso de que el bucket sobreviva a un destroy parcial. Las versiones anteriores a 7 días no tienen valor de recuperación para datos de caché.

---

## 7. Decisiones de API (API Gateway)

### 7.1 HTTP API vs REST API

**Decisión:** HTTP API (payload format 2.0).

| Característica | HTTP API | REST API |
|---|---|---|
| Precio por millón de requests | $1.00 | $3.50 |
| Latencia añadida | ~6ms | ~11ms |
| Throttling nativo | Sí | Sí |
| WAF integration | No | Sí |
| Request validation | No | Sí |
| API Keys | No | Sí |

Para este challenge (una sola ruta `POST /process`, sin API Keys, sin WAF), HTTP API es suficiente y cuesta 3.5x menos. La payload format 2.0 simplifica el handling del evento en Lambda (el body viene parseado directamente).

### 7.2 Throttling: burst=10, rate=5 rps

**Decisión:** límites conservadores para proteger Redis y Lambda en QA.

5 requests por segundo sostenidos y un burst de hasta 10 previene que una llamada de prueba con loop infinito genere costo excesivo. En producción se ajustaría según capacity planning.

### 7.3 CORS: allow-origins=*

**Decisión:** CORS abierto en QA.

Para el challenge el cliente puede ser cualquier herramienta (curl, Postman, browser). En producción se restringiría a los dominios del frontend. CORS no es una medida de seguridad para APIs server-to-server (curl no envía preflight), así que este ajuste solo afecta a llamadas desde browsers.

### 7.4 Auto-deploy en stage `$default`

**Decisión:** `auto_deploy = true` en el stage `$default`.

Elimina el paso manual de hacer deploy del API Gateway después de cada cambio de configuración. Para producción se usarían stages explícitos (`v1`, `v2`) con deployment manual para control de versiones.

---

## 8. Decisiones de identidad y acceso (IAM)

### 8.1 Dos roles con least privilege

**Decisión:** un rol para cada función Lambda con los permisos mínimos necesarios.

**Role `processor`:**
- `AWSLambdaVPCAccessExecutionRole` (managed policy): permite crear ENIs en la VPC y escribir logs básicos
- Policy inline custom: solo `s3:PutObject` y `s3:GetObject` en `{bucket_arn}/results/*` (no permite listar el bucket, ni acceder a otros prefijos)

**Role `expiry_checker`:**
- `AWSLambdaBasicExecutionRole` (managed policy): solo escritura de logs a CloudWatch
- Policy inline custom: solo `sns:Publish` en `*` (necesario porque el topic ARN se conoce en runtime)

La alternativa de un solo rol con todos los permisos se descartó: si la función `expiry_checker` fuera comprometida, no debería poder leer/escribir en S3 ni acceder a la VPC.

### 8.2 Sin key pairs, sin access keys en código

**Decisión:** las funciones Lambda usan el rol IAM asignado, no credenciales hardcodeadas.

Las credenciales se inyectan automáticamente por el runtime de Lambda vía el rol de ejecución. Esto sigue el principio de "no credentials in code" y permite revocar acceso simplemente cambiando las políticas del rol.

---

## 9. Decisiones de observabilidad y alertas

### 9.1 CloudWatch Logs con retención de 7 días

**Decisión:** `retention_in_days = 7` en todos los log groups.

CloudWatch Logs cobra $0.50/GB/mes de almacenamiento después del Free Tier (5 GB). Para un challenge de 10 días con tráfico mínimo, 7 días de retención es suficiente para debugging sin acumular logs post-expiración.

Los log groups creados explícitamente en Terraform (en lugar de dejar que Lambda los cree automáticamente) permiten:
- Controlar la retención desde el principio
- Aplicar tags via `default_tags`
- Incluirlos en `terraform destroy`

### 9.2 SNS + EventBridge para alerta de expiración

**Decisión:** EventBridge (rate 1 día) invoca Lambda `expiry_checker` que publica en SNS → email.

La alternativa de una CloudWatch Alarm con métrica custom requeriría emitir la métrica manualmente desde algún proceso. SNS + Lambda es más flexible: la lógica de "cuándo alertar" (≤3 días restantes) vive en código Python, no en configuración de CloudWatch.

EventBridge `rate(1 day)` es el scheduler más simple y de menor costo para una tarea diaria.

---

## 10. Decisiones de Terraform (IaC)

### 10.1 Versiones fijadas

**Decisión:** `terraform >= 1.7`, `aws ~> 5.40`, `null ~> 3.2`, `archive ~> 2.4`.

Fijar versiones con operador `~>` (compatible releases) previene que un upgrade automático del provider rompa el plan. `~> 5.40` permite cualquier versión `5.x` >= 5.40 pero no `6.x`.

### 10.2 State en local (no remote)

**Decisión:** state local (`terraform.tfstate`) para este challenge.

Para un challenge individual de 10 días, un backend remoto (S3 + DynamoDB para locking) agregaría infraestructura de soporte para gestionar la infraestructura principal. El `.gitignore` excluye el state file del repositorio (contiene ARNs y valores sensibles en texto plano).

En producción: S3 backend con encriptación + DynamoDB para state locking.

### 10.3 terraform.tfvars fuera del repo

**Decisión:** `terraform.tfvars` en `.gitignore`, se distribuye solo `terraform.tfvars.example`.

El `tfvars` contiene el email del owner y podría contener credenciales en otros contextos. `tfvars.example` documenta la estructura sin exponer valores reales.

### 10.4 depends_on implícito via referencias

**Decisión:** no usar `depends_on` explícito donde se puede expresar la dependencia via referencias.

Cuando un recurso usa `module.iam.processor_role_arn` como valor, Terraform infiere automáticamente que debe crear el módulo IAM primero. `depends_on` explícito solo se usa cuando la dependencia es de comportamiento (no de valor), como en `aws_s3_bucket_policy → aws_s3_bucket_public_access_block` (el block public access debe existir antes de aplicar la policy).

---

## 11. Decisiones de costos

### 11.1 Tabla de costos del periodo

| Recurso | Tipo de cobro | Estimado 10 días |
|---|---|---|
| NAT Gateway | $0.045/hr × 240h | **$10.80** |
| ElastiCache `cache.t3.micro` | Free Tier (750h/mes) | $0.00 |
| Lambda (ambas funciones) | Free Tier (1M req/mes) | $0.00 |
| API Gateway HTTP API | Free Tier (1M req/mes) | $0.00 |
| S3 Standard | Free Tier (5 GB, 20K GET, 2K PUT) | $0.00 |
| CloudWatch Logs | Free Tier (5 GB) | $0.00 |
| SNS | Free Tier (1M notificaciones) | $0.00 |
| VPC Endpoint S3 Gateway | Sin costo | $0.00 |
| **TOTAL ESTIMADO** | | **~$10.80** |

El NAT Gateway es el único componente con costo real. Es el costo de tener Lambda en VPC privada con acceso a internet.

### 11.2 Medidas de control de costos

- **ExpiryDate tag** en todos los recursos para identificación en Cost Explorer
- **EventBridge + Lambda** enviará alertas por email cuando queden ≤3 días para la expiración
- **Script `destroy.ps1`** con verificación de recursos residuales (NAT GWs, ElastiCache) post-destrucción
- **Lifecycle rules en S3** para expirar objetos automáticamente (previene acumulación si el bucket sobrevive)
- **Retención de logs a 7 días** para evitar costo de almacenamiento en CloudWatch

---

## 12. Trade-offs aceptados

| Decisión | Beneficio | Costo/riesgo aceptado |
|---|---|---|
| Cuenta root para despliegue | Velocidad de entrega del challenge | Mala práctica de seguridad. En producción: IAM User con least privilege o IAM Role federado |
| Un solo NAT Gateway | Ahorro ~$10.80 en el periodo | Si `us-east-1a` falla, Lambda en `us-east-1b` pierde salida a internet |
| ElastiCache single-node | Free Tier, costo $0 | Si el nodo falla, caché no disponible hasta recuperación (~1-2 min) |
| State local (no S3 backend) | Simplicidad, sin infraestructura adicional | No hay locking: dos operaciones `apply` simultáneas corromperían el state |
| TTL Redis de 60 segundos | Demo de HIT/MISS en tiempo real | Caché corto, hit rate bajo en producción real — se ajustaría según patrones de uso |
| CORS `allow-origins=*` | Flexibilidad en entorno QA | No válido para producción — se restringiría a dominios conocidos |
| DenyNonSSL sin excepción para root | Seguridad máxima en tránsito | El CLI de AWS (root) no puede hacer `head-bucket` directamente — S3 solo accesible via Lambda |
