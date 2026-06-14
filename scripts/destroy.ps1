# =============================================================
# DESTROY SCRIPT — SRE Challenge
# Ejecutar cuando la prueba técnica esté completa
# O si han pasado más de 10 días desde el despliegue
# =============================================================

param(
    [string]$BucketName = "",
    [switch]$Force = $false
)

Write-Host "========================================" -ForegroundColor Red
Write-Host "  DESTRUCCION TOTAL DE INFRAESTRUCTURA" -ForegroundColor Red
Write-Host "========================================" -ForegroundColor Red
Write-Host ""

if (-not $Force) {
    $confirm = Read-Host "¿Confirmas destruir TODO? Escribe 'DESTRUIR' para continuar"
    if ($confirm -ne "DESTRUIR") {
        Write-Host "Cancelado." -ForegroundColor Yellow
        exit 0
    }
}

Set-Location "$PSScriptRoot\..\terraform"

# Paso 1: Obtener nombre del bucket desde outputs de Terraform
if (-not $BucketName) {
    $BucketName = terraform output -raw s3_bucket_name 2>$null
}

if ($BucketName) {
    Write-Host "Vaciando bucket S3: $BucketName" -ForegroundColor Yellow
    aws s3 rm "s3://$BucketName" --recursive --profile sre-challenge
}

# Paso 2: Destruir toda la infraestructura
Write-Host "Ejecutando terraform destroy..." -ForegroundColor Yellow
terraform destroy --auto-approve

# Paso 3: Verificar que no quedaron recursos
Write-Host ""
Write-Host "Verificando recursos residuales..." -ForegroundColor Yellow
aws ec2 describe-nat-gateways `
    --filter "Name=state,Values=available,pending" `
    --query "NatGateways[].NatGatewayId" `
    --output text --profile sre-challenge

aws elasticache describe-cache-clusters `
    --query "CacheClusters[].CacheClusterId" `
    --output text --profile sre-challenge

Write-Host ""
Write-Host "Destruccion completada." -ForegroundColor Green
