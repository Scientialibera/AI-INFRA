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

# Function to parse TOML (simplified - handles basic TOML)
function Get-TomlConfig {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        Write-Error "Config file not found: $Path"
        exit 1
    }

    $config = @{}
    $currentSection = $null

    Get-Content $Path | ForEach-Object {
        $line = $_.Trim()

        # Skip comments and empty lines
        if ($line -match '^#' -or $line -eq '') {
            return
        }

        # Section headers [section] or [section.subsection]
        if ($line -match '^\[(.+)\]$') {
            $currentSection = $matches[1]
            $sections = $currentSection -split '\.'

            # Create nested hashtables
            $current = $config
            for ($i = 0; $i -lt $sections.Length; $i++) {
                if (-not $current.ContainsKey($sections[$i])) {
                    $current[$sections[$i]] = @{}
                }
                if ($i -lt $sections.Length - 1) {
                    $current = $current[$sections[$i]]
                }
            }
            return
        }

        # Key-value pairs
        if ($line -match '^(\w+)\s*=\s*(.+)$') {
            $key = $matches[1]
            $value = $matches[2].Trim()

            # Parse value type
            if ($value -match '^\[(.+)\]$') {
                # Array
                $arrayContent = $matches[1]
                if ($arrayContent -match '^\s*\{') {
                    # Array of objects - parse as JSON
                    $value = $arrayContent | ConvertFrom-Json
                } else {
                    # Array of strings
                    $value = $arrayContent -split ',' | ForEach-Object {
                        $_.Trim().Trim('"').Trim("'")
                    }
                }
            } elseif ($value -eq 'true') {
                $value = $true
            } elseif ($value -eq 'false') {
                $value = $false
            } elseif ($value -match '^\d+$') {
                $value = [int]$value
            } else {
                # String - remove quotes
                $value = $value.Trim('"').Trim("'")
            }

            # Add to config
            if ($currentSection) {
                $sections = $currentSection -split '\.'
                $current = $config
                foreach ($section in $sections) {
                    $current = $current[$section]
                }
                $current[$key] = $value
            } else {
                $config[$key] = $value
            }
        }
    }

    return $config
}

Write-Host "Loading configuration from $ConfigFile..." -ForegroundColor Cyan
$config = Get-TomlConfig -Path $ConfigFile

# Extract configuration values
$projectName = $config.project.name
$locations = $config.project.locations
$environment = $config.project.environment
$resourceGroupNameTemplate = $config.project.resourceGroupName
$adminEmails = $config.admin.emails

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
Write-Host "  Environment: $environment"
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
            Write-Host "    ✓ Found: $user" -ForegroundColor Green
        } else {
            Write-Host "    ✗ User not found in Azure AD: $email" -ForegroundColor Red
            Write-Host "      Make sure the email is a valid Azure AD user principal name (UPN)" -ForegroundColor Yellow
            exit 1
        }
    } catch {
        Write-Host "    ✗ Error looking up user: $email" -ForegroundColor Red
        Write-Host "      $_" -ForegroundColor Yellow
        exit 1
    }
}

Write-Host "`n✓ Resolved $($adminObjectIds.Count) admin user(s)" -ForegroundColor Green

# Function to test if a region supports required services
function Test-RegionAvailability {
    param([string]$Region)

    Write-Host "`n  Testing region: $Region..." -ForegroundColor Cyan

    # Check if OpenAI is available in the region (if enabled)
    if ($config.services.openai.enabled) {
        Write-Host "    Checking OpenAI availability..." -ForegroundColor Gray
        $openaiLocations = az provider show --namespace Microsoft.CognitiveServices --query "resourceTypes[?resourceType=='accounts'].locations[]" -o json | ConvertFrom-Json
        if ($openaiLocations -notcontains $Region) {
            Write-Host "    ✗ OpenAI not available in $Region" -ForegroundColor Yellow
            return $false
        }
    }

    # Check if Cosmos DB is available (if enabled)
    if ($config.services.cosmosdb.enabled) {
        Write-Host "    Checking Cosmos DB availability..." -ForegroundColor Gray
        $cosmosLocations = az provider show --namespace Microsoft.DocumentDB --query "resourceTypes[?resourceType=='databaseAccounts'].locations[]" -o json | ConvertFrom-Json
        if ($cosmosLocations -notcontains $Region) {
            Write-Host "    ✗ Cosmos DB not available in $Region" -ForegroundColor Yellow
            return $false
        }
    }

    # Check if Container Apps is available (if enabled)
    if ($config.services.containerApps.enabled) {
        Write-Host "    Checking Container Apps availability..." -ForegroundColor Gray
        $containerAppsLocations = az provider show --namespace Microsoft.App --query "resourceTypes[?resourceType=='managedEnvironments'].locations[]" -o json | ConvertFrom-Json
        if ($containerAppsLocations -notcontains $Region) {
            Write-Host "    ✗ Container Apps not available in $Region" -ForegroundColor Yellow
            return $false
        }
    }

    Write-Host "    ✓ Region $Region supports all required services" -ForegroundColor Green
    return $true
}

# Find the first available region
Write-Host "`nTesting region availability..." -ForegroundColor Yellow
$selectedLocation = $null
foreach ($location in $locations) {
    if (Test-RegionAvailability -Region $location) {
        $selectedLocation = $location
        Write-Host "`n✓ Selected region: $selectedLocation" -ForegroundColor Green
        break
    }
}

if (-not $selectedLocation) {
    Write-Host "`n✗ None of the specified regions support all required services!" -ForegroundColor Red
    Write-Host "  Tried regions: $($locations -join ', ')" -ForegroundColor Yellow
    Write-Host "  Please update config.toml with different regions or disable some services." -ForegroundColor Yellow
    exit 1
}

# Update resource group name with selected location
$resourceGroupName = $resourceGroupNameTemplate -replace '\{location\}', $selectedLocation
if ($resourceGroupName -notmatch $selectedLocation) {
    # If no {location} placeholder, append it
    $resourceGroupName = "$resourceGroupNameTemplate-$selectedLocation"
}

Write-Host "`nFinal Configuration:" -ForegroundColor Yellow
Write-Host "  Selected Region: $selectedLocation"
Write-Host "  Resource Group: $resourceGroupName"

# Create resource group if it doesn't exist
Write-Host "`nEnsuring resource group exists..." -ForegroundColor Cyan
$rgExists = az group exists --name $resourceGroupName | ConvertFrom-Json
if (-not $rgExists) {
    Write-Host "Creating resource group: $resourceGroupName" -ForegroundColor Green
    if (-not $WhatIf) {
        az group create --name $resourceGroupName --location $selectedLocation
    }
} else {
    Write-Host "Resource group already exists: $resourceGroupName" -ForegroundColor Green
}

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
    
    # Service enablement flags
    enableOpenAI = $config.services.openai.enabled
    enableCosmosDB = $config.services.cosmosdb.enabled
    enableDataLake = $config.services.datalake.enabled
    enableSQLDB = $config.services.sqldb.enabled
    enableAISearch = $config.services.aisearch.enabled
    enableContainerApps = $config.services.containerApps.enabled
    enableContainerRegistry = $config.services.containerRegistry.enabled
    enableKeyVault = $config.services.keyVault.enabled
    enableMonitoring = $config.services.monitoring.enabled
    enableAPIM = if ($config.services.apim) { $config.services.apim.enabled } else { $false }
    enableFrontDoor = if ($config.services.frontDoor) { $config.services.frontDoor.enabled } else { $false }
    enableRedis = if ($config.services.redis) { $config.services.redis.enabled } else { $false }
    enablePolicy = if ($config.policy) { $config.policy.enabled } else { $false }
    
    # OpenAI parameters
    openAIDeployments = $config.services.openai.deployments
    openAIContentFilterPolicy = if ($config.services.openai.contentFilterPolicy) { $config.services.openai.contentFilterPolicy } else { "default" }
    
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
    sqlAllowedIpRanges = if ($config.services.sqldb.allowedIpRanges) { $config.services.sqldb.allowedIpRanges } else { @() }
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

# Convert parameters to JSON
$parametersJson = $parameters | ConvertTo-Json -Depth 10 -Compress

# Create a temporary parameters file
$tempParamsFile = [System.IO.Path]::GetTempFileName()
$parametersJson | Out-File -FilePath $tempParamsFile -Encoding UTF8

Write-Host "`nDeploying infrastructure..." -ForegroundColor Cyan
Write-Host "This may take 15-30 minutes depending on the services enabled..." -ForegroundColor Yellow

if ($WhatIf) {
    Write-Host "`n[WHAT-IF MODE] Would deploy with these parameters:" -ForegroundColor Magenta
    $parameters | ConvertTo-Json -Depth 10
} else {
    # Deploy using Azure CLI
    $deploymentName = "ai-landing-zone-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

    az deployment group create `
        --name $deploymentName `
        --resource-group $resourceGroupName `
        --template-file "infra/main.bicep" `
        --parameters "@$tempParamsFile" `
        --verbose

    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n✓ Deployment completed successfully!" -ForegroundColor Green

        # Get outputs
        Write-Host "`nRetrieving deployment outputs..." -ForegroundColor Cyan
        $outputs = az deployment group show `
            --name $deploymentName `
            --resource-group $resourceGroupName `
            --query properties.outputs `
            --output json | ConvertFrom-Json

        Write-Host "`nDeployment Outputs:" -ForegroundColor Yellow
        $outputs.PSObject.Properties | ForEach-Object {
            Write-Host "  $($_.Name): $($_.Value.value)"
        }
    } else {
        Write-Host "`n✗ Deployment failed!" -ForegroundColor Red
        exit 1
    }
}

# Clean up temp file
Remove-Item -Path $tempParamsFile -Force

Write-Host "`nDeployment script completed." -ForegroundColor Cyan
