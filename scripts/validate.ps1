# =============================================================
# VALIDATE SCRIPT - SRE Challenge
# Verifica que todos los recursos esten activos y funcionales
# =============================================================

$ErrorActionPreference = "Continue"
$Root = Split-Path $PSScriptRoot -Parent
$Pass = 0
$Fail = 0

function Check($label, $result) {
    if ($result) {
        Write-Host "  [OK] $label" -ForegroundColor Green
        $script:Pass++
    } else {
        Write-Host "  [FAIL] $label" -ForegroundColor Red
        $script:Fail++
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  SRE CHALLENGE - VALIDACION" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# -- AWS Conectividad --
Write-Host ""
Write-Host "[ AWS ]" -ForegroundColor Yellow
$identity = aws sts get-caller-identity --profile sre-challenge 2>$null | ConvertFrom-Json
Check "AWS CLI conectado - cuenta $($identity.Account)" ($null -ne $identity)

# -- Terraform Outputs --
Write-Host ""
Write-Host "[ Terraform ]" -ForegroundColor Yellow
Set-Location "$Root\terraform"
$outputs = terraform output -json 2>$null | ConvertFrom-Json
Check "terraform state accesible" ($null -ne $outputs)
$apiEndpoint = $outputs.api_endpoint.value
$s3Bucket    = $outputs.s3_bucket_name.value
Check "api_endpoint definido: $apiEndpoint" ($null -ne $apiEndpoint)
Check "s3_bucket_name definido: $s3Bucket" ($null -ne $s3Bucket)

# -- VPC --
Write-Host ""
Write-Host "[ VPC ]" -ForegroundColor Yellow
$vpcId = $outputs.vpc_id.value
$vpc = aws ec2 describe-vpcs --vpc-ids $vpcId --profile sre-challenge 2>$null | ConvertFrom-Json
Check "VPC activa ($vpcId)" ($vpc.Vpcs.Count -gt 0)

$nats = aws ec2 describe-nat-gateways --filter "Name=state,Values=available" --profile sre-challenge 2>$null | ConvertFrom-Json
Check "NAT Gateway disponible" ($nats.NatGateways.Count -gt 0)

# -- ElastiCache --
Write-Host ""
Write-Host "[ ElastiCache Redis ]" -ForegroundColor Yellow
$redis = aws elasticache describe-cache-clusters --cache-cluster-id "sre-qa-redis" --profile sre-challenge 2>$null | ConvertFrom-Json
$redisStatus = $redis.CacheClusters[0].CacheClusterStatus
Check "Redis cluster status: $redisStatus" ($redisStatus -eq "available")

# -- S3 --
Write-Host ""
Write-Host "[ S3 ]" -ForegroundColor Yellow
aws s3api head-bucket --bucket $s3Bucket --profile sre-challenge 2>$null
Check "Bucket $s3Bucket accesible" ($LASTEXITCODE -eq 0)
$s3Objects = aws s3 ls "s3://$s3Bucket/results/" --recursive --profile sre-challenge 2>$null
Check "Objetos en results/" ($null -ne $s3Objects)

# -- Lambda --
Write-Host ""
Write-Host "[ Lambda ]" -ForegroundColor Yellow
$proc = aws lambda get-function --function-name "sre-challenge-qa-processor" --profile sre-challenge 2>$null | ConvertFrom-Json
Check "Lambda processor: $($proc.Configuration.State)" ($proc.Configuration.State -eq "Active")
$expiry = aws lambda get-function --function-name "sre-challenge-qa-expiry-checker" --profile sre-challenge 2>$null | ConvertFrom-Json
Check "Lambda expiry-checker: $($expiry.Configuration.State)" ($expiry.Configuration.State -eq "Active")

# -- API Gateway - Prueba funcional --
Write-Host ""
Write-Host "[ API Gateway - Prueba funcional ]" -ForegroundColor Yellow
$body = '{"user":"validate-script","action":"test"}'

$missResponse = Invoke-WebRequest -Uri $apiEndpoint -Method POST `
    -Body $body -ContentType "application/json" -UseBasicParsing 2>$null
$missCache = $missResponse.Headers["X-Cache"]
Check "POST /process responde 200" ($missResponse.StatusCode -eq 200)
Check "Primera llamada es X-Cache: MISS" ($missCache -eq "MISS")

$hitResponse = Invoke-WebRequest -Uri $apiEndpoint -Method POST `
    -Body $body -ContentType "application/json" -UseBasicParsing 2>$null
$hitCache = $hitResponse.Headers["X-Cache"]
Check "Segunda llamada es X-Cache: HIT" ($hitCache -eq "HIT")

# -- Resumen --
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  RESULTADO: $Pass OK / $Fail FAIL" -ForegroundColor $(if ($Fail -eq 0) { "Green" } else { "Red" })
Write-Host "========================================" -ForegroundColor Cyan

if ($Fail -gt 0) { exit 1 }
