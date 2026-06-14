# Decisiones de Diseño — SRE Challenge

## 1. HTTP API Gateway vs REST API Gateway

**Decision:** HTTP API (payload format 2.0)

HTTP API es ~70% mas barato que REST API y tiene menor latencia. Para este challenge la ruta unica es POST /process, sin necesidad de API Keys, WAF, o request validation avanzada — HTTP API cubre todo eso con menor overhead.

---

## 2. Single NAT Gateway vs NAT por AZ

**Decision:** Un solo NAT Gateway en us-east-1a

Un NAT GW por AZ cuesta ~$32/mes en entorno de dos AZs. Para QA/challenge con expiración en 10 días, el costo no justifica la HA. Si tráfico de la Lambda falla porque el NAT de us-east-1a cae, la Lambda puede reintentar — aceptable para este contexto.

---

## 3. ElastiCache single-node vs cluster mode

**Decision:** Single-node (1 nodo, sin replica, sin cluster mode)

cache.t3.micro con 1 nodo entra en Free Tier (750 hrs/mes primer año). El challenge pide demostrar la capa de cache, no alta disponibilidad. Cluster mode con MultiAZ multiplicaria el costo por 2-3x.

---

## 4. VPC Endpoint para S3 (Gateway type)

**Decision:** VPC Endpoint Gateway para S3

El trafico Lambda→S3 va por la red privada de AWS sin pasar por el NAT Gateway. Beneficio doble: (1) evita cobro de procesamiento NAT ($0.045/GB) en transferencias S3, (2) mejor seguridad (trafico no sale a internet). Los Gateway endpoints no tienen costo adicional.

---

## 5. Security Groups sin reglas inline (circular dependency fix)

**Decision:** aws_security_group + aws_security_group_rule separados

Lambda SG necesita egress al Redis SG, y Redis SG necesita ingress del Lambda SG. Terraform detecta esto como dependencia circular si se definen inline. La solucion es crear ambos SG sin reglas, y luego agregar las reglas como recursos separados que referencian los IDs ya conocidos.

---

## 6. Lambda packaging via null_resource + archive_file

**Decision:** pip install local en lambda/package/ + zip via archive_file

Alternativas descartadas:
- Docker build: requiere Docker instalado en CI/CD
- Lambda Layer: agregar complejidad para una sola dependencia (redis==5.0.1)
- ECR container image: overhead de registry para 1 funcion simple

null_resource con local-exec PowerShell corre pip install, archive_file empaqueta el directorio. Simple y reproducible en Windows sin dependencias adicionales.

---

## 7. Cache key: SHA256(json.dumps(body, sort_keys=True))

**Decision:** hash del body canonicalizado

sort_keys=True garantiza que `{"b":1,"a":2}` y `{"a":2,"b":1}` generen el mismo cache key. SHA256 evita colisiones y produce una clave de longitud fija (64 chars hex) sin caracteres especiales — segura para usar como Redis key.

---

## 8. Cuenta root de AWS

**Decision:** root account para el challenge (documentado, no recomendado)

Para velocidad de entrega del challenge se uso la cuenta root con Access Keys. En produccion esto es inaceptable — se usaria un IAM User o IAM Role con permisos minimos (least privilege). El README documenta este tradeoff explicitamente.

---

## 9. TTL de Redis: 60 segundos

**Decision:** 60s TTL para cache entries

El challenge especifica demostrar HIT/MISS en llamadas consecutivas. 60s es suficiente para hacer la segunda llamada antes de que expire. Un TTL mas largo acumula mas memoria en el cache; mas corto no deja tiempo para la demo manual.

---

## 10. Retencion de logs: 7 dias

**Decision:** CloudWatch Log Groups con retention_in_days = 7

CloudWatch Logs cobra $0.50/GB despues del Free Tier (5 GB). Para un challenge de 10 dias con trafico minimo, 7 dias de retencion cubre el periodo completo sin acumular logs innecesarios post-expiración.
