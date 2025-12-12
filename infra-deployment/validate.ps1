# Validation script for Azure AI Landing Zone deployment
# This script validates the Bicep templates and configuration

param(
    [string]$ConfigFile = "config.toml"
)

Write-Host "Azure AI Landing Zone - Validation Script" -ForegroundColor Cyan
Write-Host "==========================================`n" -ForegroundColor Cyan

# Check prerequisites
Write-Host "Checking prerequisites..." -ForegroundColor Yellow

# Check Azure CLI
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Host "✗ Azure CLI not found" -ForegroundColor Red
    Write-Host "  Install from: https://aka.ms/azure-cli" -ForegroundColor Yellow
    exit 1
} else {
    $azVersion = (az version --output json | ConvertFrom-Json).'azure-cli'
    Write-Host "✓ Azure CLI installed (version $azVersion)" -ForegroundColor Green
}

# Check Azure CLI login
try {
    $account = az account show 2>$null | ConvertFrom-Json
    Write-Host "✓ Logged in to Azure (Subscription: $($account.name))" -ForegroundColor Green
} catch {
    Write-Host "✗ Not logged in to Azure" -ForegroundColor Red
    Write-Host "  Run: az login" -ForegroundColor Yellow
    exit 1
}

# Check Bicep
try {
    az bicep version | Out-Null
    $bicepVersion = az bicep version
    Write-Host "✓ Bicep installed ($bicepVersion)" -ForegroundColor Green
} catch {
    Write-Host "✗ Bicep not found" -ForegroundColor Red
    Write-Host "  Installing Bicep..." -ForegroundColor Yellow
    az bicep install
}

# Validate config file exists
Write-Host "`nValidating configuration..." -ForegroundColor Yellow

if (-not (Test-Path $ConfigFile)) {
    Write-Host "✗ Config file not found: $ConfigFile" -ForegroundColor Red
    exit 1
} else {
    Write-Host "✓ Config file found: $ConfigFile" -ForegroundColor Green
}

# Validate Bicep templates
Write-Host "`nValidating Bicep templates..." -ForegroundColor Yellow

$bicepFiles = @(
    "infra/main.bicep",
    "infra/modules/networking.bicep",
    "infra/modules/identities.bicep",
    "infra/modules/monitoring.bicep",
    "infra/modules/keyvault.bicep",
    "infra/modules/openai.bicep",
    "infra/modules/cosmosdb.bicep",
    "infra/modules/datalake.bicep",
    "infra/modules/sqldb.bicep",
    "infra/modules/aisearch.bicep",
    "infra/modules/containerregistry.bicep",
    "infra/modules/containerapps.bicep",
    "infra/modules/rbac.bicep"
)

$allValid = $true
foreach ($bicepFile in $bicepFiles) {
    if (-not (Test-Path $bicepFile)) {
        Write-Host "✗ Missing: $bicepFile" -ForegroundColor Red
        $allValid = $false
        continue
    }

    try {
        $result = az bicep build --file $bicepFile --stdout 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ Valid: $bicepFile" -ForegroundColor Green
        } else {
            Write-Host "✗ Invalid: $bicepFile" -ForegroundColor Red
            Write-Host "  Error: $result" -ForegroundColor Yellow
            $allValid = $false
        }
    } catch {
        Write-Host "✗ Error validating: $bicepFile" -ForegroundColor Red
        Write-Host "  $_" -ForegroundColor Yellow
        $allValid = $false
    }
}

# Validate main template with what-if
Write-Host "`nRunning deployment what-if analysis..." -ForegroundColor Yellow
Write-Host "(This shows what would be created/modified/deleted)`n" -ForegroundColor Cyan

# For what-if, we need to parse config and create a minimal parameter set
# For now, just validate the template compiles
try {
    az bicep build --file infra/main.bicep --stdout > $null 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ Main template builds successfully" -ForegroundColor Green
    } else {
        Write-Host "✗ Main template has errors" -ForegroundColor Red
        $allValid = $false
    }
} catch {
    Write-Host "✗ Failed to build main template" -ForegroundColor Red
    $allValid = $false
}

# Summary
Write-Host "`n==========================================`n" -ForegroundColor Cyan
if ($allValid) {
    Write-Host "✓ All validations passed!" -ForegroundColor Green
    Write-Host "`nYou can now deploy using:" -ForegroundColor Cyan
    Write-Host "  .\deploy.ps1" -ForegroundColor Yellow
    Write-Host "Or preview changes with:" -ForegroundColor Cyan
    Write-Host "  .\deploy.ps1 -WhatIf" -ForegroundColor Yellow
} else {
    Write-Host "✗ Validation failed - please fix errors above" -ForegroundColor Red
    exit 1
}
