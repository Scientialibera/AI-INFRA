# PowerShell deployment script for Azure AI Landing Zone
# This script reads config.toml and deploys the infrastructure using Azure CLI

param(
    [string]$ConfigFile = "config.toml",
    [switch]$WhatIf
)

# Check if Azure CLI is installed
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Error "Azure CLI is not installed. Please install it from https://aka.ms/azure-cli"
    exit 1
}

# Check if user is logged in
$account = az account show 2>$null
if (-not $account) {
    Write-Host "Not logged in to Azure. Please log in..."
    az login
}

# Function to parse TOML using Python's real TOML parser
function Get-TomlConfig {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        Write-Error "Config file not found: $Path"
        exit 1
    }

    if (-not (Get-Command python3 -ErrorAction SilentlyContinue) -and -not (Get-Command python -ErrorAction SilentlyContinue)) {
        Write-Error "Python is required to parse TOML reliably. Install Python 3.11+."
        exit 1
    }

    $pythonCmd = if (Get-Command python -ErrorAction SilentlyContinue) { "python" } elseif (Get-Command python3 -ErrorAction SilentlyContinue) { "python3" } else { $null }
    if (-not $pythonCmd) {
        Write-Error "Python is required to parse TOML reliably. Install Python 3.11+."
        exit 1
    }
    $tomlJson = & $pythonCmd -c @"
import json
import pathlib
import sys

path = pathlib.Path(r'''$Path''')

try:
    import tomllib as toml
except ModuleNotFoundError:
    try:
        import tomli as toml
    except ModuleNotFoundError:
        print('TOML_PARSER_MISSING')
        sys.exit(2)

with path.open('rb') as f:
    print(json.dumps(toml.load(f)))
"@

    if ($LASTEXITCODE -ne 0 -or $tomlJson -eq 'TOML_PARSER_MISSING') {
        Write-Error "Python TOML support is missing. Install Python 3.11+ or run 'python -m pip install --user tomli'."
        exit 1
    }

    return $tomlJson | ConvertFrom-Json -AsHashtable
}

Write-Host "Loading configuration from $ConfigFile..." -ForegroundColor Cyan
$config = Get-TomlConfig -Path $ConfigFile

# Extract configuration values
$projectName = $config.project.name
$locations = $config.project.locations
$defaultEnvironment = $config.project.environment
$resourceGroupNameTemplate = $config.project.resourceGroupName
$adminEmails = $config.admin.emails

# Multi-prefix support:
# - project.prefixes = ["dev", "uat", "prod"] (preferred)
# - project.prefix = "dev" (single)
# - falls back to project.environment when neither is provided
$deploymentPrefixes = @()
if ($config.project.ContainsKey('prefixes') -and $null -ne $config.project.prefixes) {
    if ($config.project.prefixes -is [string]) {
        $deploymentPrefixes = @($config.project.prefixes)
    } else {
        $deploymentPrefixes = @($config.project.prefixes)
    }
} elseif ($config.project.ContainsKey('prefix') -and $null -ne $config.project.prefix) {
    $deploymentPrefixes = @($config.project.prefix)
} else {
    $deploymentPrefixes = @($defaultEnvironment)
}

$deploymentPrefixes = @($deploymentPrefixes | ForEach-Object { "$_".Trim() } | Where-Object { $_ -ne '' } | Select-Object -Unique)
if ($deploymentPrefixes.Count -eq 0) {
    Write-Error "No deployment prefixes found. Set project.prefixes (array), project.prefix (string), or project.environment."
    exit 1
}

# Ensure locations is an array
if ($locations -is [string]) {
    $locations = @($locations)
}

# Ensure admin emails is an array
if ($adminEmails -is [string]) {
    $adminEmails = @($adminEmails)
}

Write-Host "`nDeployment Configuration:" -ForegroundColor Yellow
Write-Host "  Project Name: $projectName"
Write-Host "  Fallback Regions: $($locations -join ' -> ')"
Write-Host "  Deployment Prefixes: $($deploymentPrefixes -join ', ')"
Write-Host "  Admin Emails: $($adminEmails -join ', ')"

# Resolve admin emails to Azure AD Object IDs
Write-Host "`nResolving admin user Object IDs..." -ForegroundColor Cyan
$adminObjectIds = @()
foreach ($email in $adminEmails) {
    Write-Host "  Looking up: $email" -ForegroundColor Gray
    try {
        $user = az ad user show --id $email --query id -o tsv 2>$null
        if ($user) {
            $adminObjectIds += $user
            Write-Host "     Found: $user" -ForegroundColor Green
        } else {
            Write-Host "     User not found in Azure AD: $email" -ForegroundColor Red
            Write-Host "      Make sure the email is a valid Azure AD user principal name (UPN)" -ForegroundColor Yellow
            exit 1
        }
    } catch {
        Write-Host "     Error looking up user: $email" -ForegroundColor Red
        Write-Host "      $_" -ForegroundColor Yellow
        exit 1
    }
}

Write-Host "`n Resolved $($adminObjectIds.Count) admin user(s)" -ForegroundColor Green

# Function to test if a region supports required services
function Normalize-Region {
    param([string]$Value)

    return ($Value -replace '\s', '').ToLowerInvariant()
}

function Test-RegionAvailability {
    param([string]$Region)

    Write-Host "`n  Testing region: $Region..." -ForegroundColor Cyan
    $normalizedRegion = Normalize-Region $Region

    # Check if OpenAI is available in the region (if enabled)
    if ($config.services.openai.enabled) {
        Write-Host "    Checking OpenAI availability..." -ForegroundColor Gray
        $openaiLocations = az provider show --namespace Microsoft.CognitiveServices --query "resourceTypes[?resourceType=='accounts'].locations[]" -o json | ConvertFrom-Json
        $normalizedOpenAILocations = @($openaiLocations | ForEach-Object { Normalize-Region $_ })
        if ($normalizedOpenAILocations -notcontains $normalizedRegion) {
            Write-Host "     OpenAI not available in $Region" -ForegroundColor Yellow
            return $false
        }
    }

    # Check if Cosmos DB is available (if enabled)
    if ($config.services.cosmosdb.enabled) {
        Write-Host "    Checking Cosmos DB availability..." -ForegroundColor Gray
        $cosmosLocations = az provider show --namespace Microsoft.DocumentDB --query "resourceTypes[?resourceType=='databaseAccounts'].locations[]" -o json | ConvertFrom-Json
        $normalizedCosmosLocations = @($cosmosLocations | ForEach-Object { Normalize-Region $_ })
        if ($normalizedCosmosLocations -notcontains $normalizedRegion) {
            Write-Host "     Cosmos DB not available in $Region" -ForegroundColor Yellow
            return $false
        }
    }

    # Check if Container Apps is available (if enabled)
    if ($config.services.containerApps.enabled) {
        Write-Host "    Checking Container Apps availability..." -ForegroundColor Gray
        $containerAppsLocations = az provider show --namespace Microsoft.App --query "resourceTypes[?resourceType=='managedEnvironments'].locations[]" -o json | ConvertFrom-Json
        $normalizedContainerAppsLocations = @($containerAppsLocations | ForEach-Object { Normalize-Region $_ })
        if ($normalizedContainerAppsLocations -notcontains $normalizedRegion) {
            Write-Host "     Container Apps not available in $Region" -ForegroundColor Yellow
            return $false
        }
    }

    Write-Host "     Region $Region supports all required services" -ForegroundColor Green
    return $true
}

# Find the first available region
Write-Host "`nTesting region availability..." -ForegroundColor Yellow
$selectedLocation = $null
foreach ($location in $locations) {
    if (Test-RegionAvailability -Region $location) {
        $selectedLocation = $location
        Write-Host "`n Selected region: $selectedLocation" -ForegroundColor Green
        break
    }
}

if (-not $selectedLocation) {
    Write-Host "`n None of the specified regions support all required services!" -ForegroundColor Red
    Write-Host "  Tried regions: $($locations -join ', ')" -ForegroundColor Yellow
    Write-Host "  Please update config.toml with different regions or disable some services." -ForegroundColor Yellow
    exit 1
}

function Get-BicepExecutable {
    $cmd = Get-Command bicep -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    $wingetBicep = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages\Microsoft.Bicep_Microsoft.Winget.Source_8wekyb3d8bbwe\bicep.exe'
    if (Test-Path $wingetBicep) {
        return $wingetBicep
    }

    throw 'Bicep CLI not found. Install Bicep or ensure it is on PATH.'
}

$bicepExe = Get-BicepExecutable
$tempTemplateFile = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), '.json')

Write-Host "`nCompiling Bicep template..." -ForegroundColor Cyan
& $bicepExe build "infra/main.bicep" --outfile $tempTemplateFile
if ($LASTEXITCODE -ne 0) {
    Remove-Item -Path $tempTemplateFile -Force -ErrorAction SilentlyContinue
    exit $LASTEXITCODE
}

Write-Host "`nDeploying infrastructure..." -ForegroundColor Cyan
Write-Host "This may take 15-30 minutes depending on the services enabled..." -ForegroundColor Yellow

foreach ($prefix in $deploymentPrefixes) {
    $environment = $prefix
    $resourceGroupName = $resourceGroupNameTemplate

    $hasLocationPlaceholder = $resourceGroupName -match '\{location\}'
    $hasPrefixPlaceholder = $resourceGroupName -match '\{prefix\}|\{environment\}'

    $resourceGroupName = $resourceGroupName -replace '\{location\}', $selectedLocation
    $resourceGroupName = $resourceGroupName -replace '\{prefix\}', $prefix
    $resourceGroupName = $resourceGroupName -replace '\{environment\}', $prefix

    if (-not $hasPrefixPlaceholder -and $deploymentPrefixes.Count -gt 1) {
        $resourceGroupName = "$resourceGroupName-$prefix"
    }
    if (-not $hasLocationPlaceholder) {
        $resourceGroupName = "$resourceGroupName-$selectedLocation"
    }

    Write-Host "`nFinal Configuration:" -ForegroundColor Yellow
    Write-Host "  Prefix/Environment: $prefix"
    Write-Host "  Selected Region: $selectedLocation"
    Write-Host "  Resource Group: $resourceGroupName"

    # Create resource group if it doesn't exist
    Write-Host "`nEnsuring resource group exists..." -ForegroundColor Cyan
    $rgExists = az group exists --name $resourceGroupName | ConvertFrom-Json
    if (-not $rgExists) {
        Write-Host "Creating resource group: $resourceGroupName" -ForegroundColor Green
        # What-if runs at resource-group scope still require the RG to exist.
        az group create --name $resourceGroupName --location $selectedLocation | Out-Null
    } else {
        Write-Host "Resource group already exists: $resourceGroupName" -ForegroundColor Green
    }

    $dataLakeContainers = @(
        $(if ($config.services.datalake.ContainsKey('containers') -and $config.services.datalake.containers) {
            $config.services.datalake.containers
        } else {
            'data'
        })
    )

    # Build parameters for Bicep deployment
    $parameters = @{
        # Core parameters
        projectName = $projectName
        location = $selectedLocation
        environment = $environment
        adminObjectIds = $adminObjectIds
        
        # Networking
        enableVNet = $config.networking.enabled
        vnetAddressPrefix = $config.networking.vnetAddressPrefix
        containerAppsSubnetPrefix = $config.networking.containerAppsSubnetPrefix
        privateEndpointSubnetPrefix = $config.networking.privateEndpointSubnetPrefix
        sqlSubnetPrefix = $config.networking.sqlSubnetPrefix
        apimSubnetPrefix = if ($config.networking.apimSubnetPrefix) { $config.networking.apimSubnetPrefix } else { "10.0.4.0/27" }
        
        # Service enablement flags
        enableOpenAI = $config.services.openai.enabled
        openAIPrivateEndpointEnabled = if ($config.services.openai.ContainsKey('privateEndpointEnabled')) { $config.services.openai.privateEndpointEnabled } else { $true }
        enableCosmosDB = $config.services.cosmosdb.enabled
        cosmosPrivateEndpointEnabled = if ($config.services.cosmosdb.ContainsKey('privateEndpointEnabled')) { $config.services.cosmosdb.privateEndpointEnabled } else { $true }
        enableDataLake = $config.services.datalake.enabled
        dataLakePrivateEndpointEnabled = if ($config.services.datalake.ContainsKey('privateEndpointEnabled')) { $config.services.datalake.privateEndpointEnabled } else { $true }
        enableSQLDB = $config.services.sqldb.enabled
        sqlPrivateEndpointEnabled = if ($config.services.sqldb.ContainsKey('privateEndpointEnabled')) { $config.services.sqldb.privateEndpointEnabled } else { $true }
        enableAISearch = $config.services.aisearch.enabled
        aiSearchPrivateEndpointEnabled = if ($config.services.aisearch.ContainsKey('privateEndpointEnabled')) { $config.services.aisearch.privateEndpointEnabled } else { $true }
        enableContainerApps = $config.services.containerApps.enabled
        enableContainerRegistry = $config.services.containerRegistry.enabled
        containerRegistryPrivateEndpointEnabled = if ($config.services.containerRegistry.ContainsKey('privateEndpointEnabled')) { $config.services.containerRegistry.privateEndpointEnabled } else { $true }
        enableKeyVault = $config.services.keyVault.enabled
        keyVaultPrivateEndpointEnabled = if ($config.services.keyVault.ContainsKey('privateEndpointEnabled')) { $config.services.keyVault.privateEndpointEnabled } else { $true }
        enableMonitoring = $config.services.monitoring.enabled
        enableAPIM = if ($config.services.apim) { $config.services.apim.enabled } else { $false }
        enableFrontDoor = if ($config.services.frontDoor) { $config.services.frontDoor.enabled } else { $false }
        enableRedis = if ($config.services.redis) { $config.services.redis.enabled } else { $false }
        redisPrivateEndpointEnabled = if ($config.services.redis -and $config.services.redis.ContainsKey('privateEndpointEnabled')) { $config.services.redis.privateEndpointEnabled } else { $true }
        enablePolicy = if ($config.policy) { $config.policy.enabled } else { $false }
        
        # OpenAI parameters
        openAIDeployments = $config.services.openai.deployments
        openAIContentFilterPolicy = if ($config.services.openai.ContainsKey('contentFilterPolicy')) { $config.services.openai.contentFilterPolicy } else { "default" }
        
        # Cosmos DB parameters
        cosmosEnableNoSQL = $config.services.cosmosdb.enableNoSQL
        cosmosEnableGremlin = $config.services.cosmosdb.enableGremlin
        cosmosConsistencyLevel = $config.services.cosmosdb.consistencyLevel
        cosmosEnableServerless = if ($config.services.cosmosdb.enableServerless) { $config.services.cosmosdb.enableServerless } else { $false }
        cosmosEnableAnalyticalStorage = if ($config.services.cosmosdb.enableAnalyticalStorage) { $config.services.cosmosdb.enableAnalyticalStorage } else { $false }
        cosmosAdditionalRegions = if ($config.services.cosmosdb.additionalRegions) { $config.services.cosmosdb.additionalRegions } else { @() }
        
        # SQL parameters
        sqlDatabaseSku = $config.services.sqldb.databaseSku
        sqlAdminUsername = $config.services.sqldb.adminUsername
        sqlAllowedIpRules = if ($config.services.sqldb.allowedIpRules) { $config.services.sqldb.allowedIpRules } else { @() }
        sqlZoneRedundant = if ($config.services.sqldb.zoneRedundant) { $config.services.sqldb.zoneRedundant } else { $false }
        
        # AI Search parameters
        aiSearchSku = $config.services.aisearch.sku
        aiSearchReplicaCount = if ($config.services.aisearch.replicaCount) { $config.services.aisearch.replicaCount } else { 1 }
        aiSearchPartitionCount = if ($config.services.aisearch.partitionCount) { $config.services.aisearch.partitionCount } else { 1 }
        aiSearchSemanticTier = if ($config.services.aisearch.semanticSearchTier) { $config.services.aisearch.semanticSearchTier } else { "free" }
        
        # Container Apps parameters
        containerAppsEnableDapr = if ($config.services.containerApps.enableDapr) { $config.services.containerApps.enableDapr } else { $false }
        containerAppsZoneRedundant = if ($config.services.containerApps.zoneRedundant) { $config.services.containerApps.zoneRedundant } else { $false }
        containerAppsCustomDomain = if ($config.services.containerApps.customDomain) { $config.services.containerApps.customDomain } else { @{} }
        
        # Container Registry parameters
        containerRegistrySku = $config.services.containerRegistry.sku
        containerRegistryGeoReplicationLocations = if ($config.services.containerRegistry.geoReplicationLocations) { $config.services.containerRegistry.geoReplicationLocations } else { @() }
        
        # Data Lake parameters
        dataLakeSku = $config.services.datalake.sku
        dataLakeContainers = $dataLakeContainers
        
        # Key Vault parameters
        keyVaultSku = if ($config.services.keyVault.sku) { $config.services.keyVault.sku } else { "standard" }
        keyVaultSoftDeleteRetentionDays = if ($config.services.keyVault.softDeleteRetentionInDays) { $config.services.keyVault.softDeleteRetentionInDays } else { 90 }
        
        # Monitoring parameters
        logAnalyticsRetentionDays = if ($config.services.monitoring.retentionInDays) { $config.services.monitoring.retentionInDays } else { 30 }
        
        # APIM parameters
        apimPublisherEmail = if ($config.services.apim.publisherEmail) { $config.services.apim.publisherEmail } else { "" }
        apimPublisherName = if ($config.services.apim.publisherName) { $config.services.apim.publisherName } else { "" }
        apimSku = if ($config.services.apim.sku) { $config.services.apim.sku } else { "Developer" }
        
        # Front Door parameters
        frontDoorEnableWaf = if ($config.services.frontDoor.enableWaf) { $config.services.frontDoor.enableWaf } else { $false }
        
        # Redis parameters
        redisSku = if ($config.services.redis.sku) { $config.services.redis.sku } else { "Standard" }
        redisCapacity = if ($config.services.redis.capacity) { $config.services.redis.capacity } else { 1 }
        
        # Policy parameters
        requiredTags = if ($config.policy.requiredTags) { $config.policy.requiredTags } else { @("reason", "purpose") }
        policyEnforcementMode = if ($config.policy.enforcementMode) { $config.policy.enforcementMode } else { "Default" }
        
        # Tags
        tags = $config.tags
    }

    # Convert to ARM deployment parameters file format
    $armParameters = @{
        '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
        contentVersion = '1.0.0.0'
        parameters = @{}
    }

    foreach ($key in $parameters.Keys) {
        $armParameters.parameters[$key] = @{
            value = $parameters[$key]
        }
    }

    $parametersJson = $armParameters | ConvertTo-Json -Depth 20 -Compress
    $tempParamsFile = [System.IO.Path]::GetTempFileName()
    $parametersJson | Out-File -FilePath $tempParamsFile -Encoding UTF8

    if ($WhatIf) {
        Write-Host "`n[WHAT-IF MODE][$prefix] Previewing deployment changes..." -ForegroundColor Magenta
        az deployment group what-if `
            --resource-group $resourceGroupName `
            --template-file $tempTemplateFile `
            --parameters "@$tempParamsFile"
    } else {
        # Deploy using Azure CLI
        $deploymentName = "ai-landing-zone-$prefix-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

        az deployment group create `
            --name $deploymentName `
            --resource-group $resourceGroupName `
            --template-file $tempTemplateFile `
            --parameters "@$tempParamsFile" `
            --mode Incremental `
            --verbose

        if ($LASTEXITCODE -eq 0) {
            Write-Host "`n Deployment completed successfully for prefix '$prefix'!" -ForegroundColor Green

            # Get outputs
            Write-Host "`nRetrieving deployment outputs for '$prefix'..." -ForegroundColor Cyan
            $outputs = az deployment group show `
                --name $deploymentName `
                --resource-group $resourceGroupName `
                --query properties.outputs `
                --output json | ConvertFrom-Json

            Write-Host "`nDeployment Outputs ($prefix):" -ForegroundColor Yellow
            $outputs.PSObject.Properties | ForEach-Object {
                Write-Host "  $($_.Name): $($_.Value.value)"
            }
        } else {
            Remove-Item -Path $tempParamsFile -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $tempTemplateFile -Force -ErrorAction SilentlyContinue
            Write-Host "`n Deployment failed for prefix '$prefix'!" -ForegroundColor Red
            exit 1
        }
    }

    Remove-Item -Path $tempParamsFile -Force -ErrorAction SilentlyContinue
}

Remove-Item -Path $tempTemplateFile -Force -ErrorAction SilentlyContinue

Write-Host "`nDeployment script completed." -ForegroundColor Cyan
