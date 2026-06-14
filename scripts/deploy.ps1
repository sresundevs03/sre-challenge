# =============================================================
# DEPLOY SCRIPT — SRE Challenge
# Instala dependencias, empaqueta Lambda y aplica Terraform
# =============================================================

param(
    [switch]$PlanOnly = $false,
    [switch]$SkipBuild = $false
)

$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  SRE CHALLENGE — DEPLOY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ── Verificar prerequisitos ───────────────────────────────────────────────────
Write-Host "Verificando prerequisitos..." -ForegroundColor Yellow

$tf = Get-Command terraform -ErrorAction SilentlyContinue
if (-not $tf) {
    $tfPath = "$env:USERPROFILE\AppData\Local\Programs\terraform\terraform.exe"
    if (Test-Path $tfPath) { $env:PATH += ";$env:USERPROFILE\AppData\Local\Programs\terraform" }
    else { Write-Error "Terraform no encontrado. Instalar en: https://developer.hashicorp.com/terraform/downloads"; exit 1 }
}

$awsId = aws sts get-caller-identity --profile sre-challenge --query "Account" --output text 2>$null
if (-not $awsId) { Write-Error "AWS profile 'sre-challenge' no configurado."; exit 1 }
Write-Host "AWS Account: $awsId" -ForegroundColor Green

# ── Build Lambda package ───────────────────────────────────────────────────────
if (-not $SkipBuild) {
    Write-Host ""
    Write-Host "Construyendo paquete Lambda..." -ForegroundColor Yellow

    $pkgDir = "$Root\lambda\package"
    if (Test-Path $pkgDir) { Remove-Item $pkgDir -Recurse -Force }
    New-Item $pkgDir -ItemType Directory | Out-Null

    python -m pip install -r "$Root\lambda\requirements.txt" -t $pkgDir --quiet
    Copy-Item "$Root\lambda\handler.py" $pkgDir
    Copy-Item "$Root\lambda\expiry_checker.py" $pkgDir

    Write-Host "Lambda package listo." -ForegroundColor Green
}

# ── Terraform ─────────────────────────────────────────────────────────────────
Set-Location "$Root\terraform"

Write-Host ""
Write-Host "Inicializando Terraform..." -ForegroundColor Yellow
terraform init -upgrade

Write-Host ""
Write-Host "Validando configuracion..." -ForegroundColor Yellow
terraform validate

Write-Host ""
if ($PlanOnly) {
    Write-Host "Ejecutando terraform plan..." -ForegroundColor Yellow
    terraform plan
    Write-Host ""
    Write-Host "Plan completo. Usa -PlanOnly:`$false para aplicar." -ForegroundColor Cyan
} else {
    Write-Host "Ejecutando terraform plan..." -ForegroundColor Yellow
    terraform plan -out=tfplan

    Write-Host ""
    $confirm = Read-Host "¿Aplicar el plan? (yes/no)"
    if ($confirm -eq "yes") {
        terraform apply tfplan
        Remove-Item tfplan -ErrorAction SilentlyContinue

        Write-Host ""
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "  DEPLOY EXITOSO" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
        terraform output
    } else {
        Write-Host "Deploy cancelado." -ForegroundColor Yellow
        Remove-Item tfplan -ErrorAction SilentlyContinue
    }
}
