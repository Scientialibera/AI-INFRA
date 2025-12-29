// Main Bicep orchestration file for Azure AI Landing Zone
// This file orchestrates the deployment of all infrastructure components

targetScope = 'resourceGroup'

// =============================================================================
// CORE PARAMETERS
// =============================================================================

@description('Project name prefix for resource naming')
param projectName string

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Environment (dev, staging, prod)')
param environment string

@description('Admin user Object IDs for RBAC assignments (resolved from emails by deploy script)')
param adminObjectIds array = []

@description('Tags to apply to all resources')
param tags object = {}

// =============================================================================
// NETWORKING PARAMETERS
// =============================================================================

@description('Enable Virtual Network and private endpoints')
param enableVNet bool = true

@description('VNet address prefix')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Container Apps subnet prefix')
param containerAppsSubnetPrefix string = '10.0.0.0/23'

@description('Private endpoint subnet prefix')
param privateEndpointSubnetPrefix string = '10.0.2.0/24'

@description('SQL subnet prefix')
param sqlSubnetPrefix string = '10.0.3.0/24'

// =============================================================================
// SERVICE ENABLEMENT FLAGS
// =============================================================================

@description('Enable OpenAI Service')
param enableOpenAI bool = true

@description('Enable Cosmos DB')
param enableCosmosDB bool = true

@description('Enable Data Lake Storage')
param enableDataLake bool = true

@description('Enable SQL Database')
param enableSQLDB bool = true

@description('Enable AI Search')
param enableAISearch bool = true

@description('Enable Container Apps')
param enableContainerApps bool = true

@description('Enable Container Registry')
param enableContainerRegistry bool = true

@description('Enable Key Vault')
param enableKeyVault bool = true

@description('Enable Monitoring')
param enableMonitoring bool = true

@description('Enable API Management')
param enableAPIM bool = false

@description('Enable Azure Front Door')
param enableFrontDoor bool = false

@description('Enable Redis Cache')
param enableRedis bool = false

@description('Enable Azure Policy for required tags')
param enablePolicy bool = false

// =============================================================================
// OPENAI PARAMETERS
// =============================================================================

@description('OpenAI deployments configuration')
param openAIDeployments array = []

@description('OpenAI content filter policy name')
param openAIContentFilterPolicy string = 'default'

// =============================================================================
// COSMOS DB PARAMETERS
// =============================================================================

@description('Cosmos DB - Enable NoSQL API')
param cosmosEnableNoSQL bool = true

@description('Cosmos DB - Enable Gremlin API')
param cosmosEnableGremlin bool = true

@description('Cosmos DB - Consistency level')
param cosmosConsistencyLevel string = 'Session'

@description('Cosmos DB - Enable serverless mode')
param cosmosEnableServerless bool = false

@description('Cosmos DB - Enable analytical storage')
param cosmosEnableAnalyticalStorage bool = false

@description('Cosmos DB - Additional regions for geo-replication')
param cosmosAdditionalRegions array = []

// =============================================================================
// SQL DATABASE PARAMETERS
// =============================================================================

@description('SQL Database SKU')
param sqlDatabaseSku string = 'S1'

@description('SQL Admin Username')
param sqlAdminUsername string = 'sqladmin'

@description('SQL allowed IP ranges (CIDR notation)')
param sqlAllowedIpRanges array = []

@description('SQL Database zone redundancy')
param sqlZoneRedundant bool = false

// =============================================================================
// AI SEARCH PARAMETERS
// =============================================================================

@description('AI Search SKU')
param aiSearchSku string = 'standard'

@description('AI Search replica count')
param aiSearchReplicaCount int = 1

@description('AI Search partition count')
param aiSearchPartitionCount int = 1

@description('AI Search semantic search tier (free, standard)')
param aiSearchSemanticTier string = 'free'

// =============================================================================
// CONTAINER APPS PARAMETERS
// =============================================================================

@description('Enable Dapr for Container Apps')
param containerAppsEnableDapr bool = false

@description('Enable zone redundancy for Container Apps')
param containerAppsZoneRedundant bool = false

@description('Custom domain configuration for Container Apps')
param containerAppsCustomDomain object = {}

// =============================================================================
// CONTAINER REGISTRY PARAMETERS
// =============================================================================

@description('Container Registry SKU')
param containerRegistrySku string = 'Premium'

@description('Container Registry geo-replication locations')
param containerRegistryGeoReplicationLocations array = []

// =============================================================================
// DATA LAKE PARAMETERS
// =============================================================================

@description('Data Lake Storage SKU')
param dataLakeSku string = 'Standard_LRS'

// =============================================================================
// KEY VAULT PARAMETERS
// =============================================================================

@description('Key Vault SKU (standard, premium)')
param keyVaultSku string = 'standard'

@description('Key Vault soft delete retention days')
param keyVaultSoftDeleteRetentionDays int = 90

// =============================================================================
// MONITORING PARAMETERS
// =============================================================================

@description('Log Analytics retention in days')
param logAnalyticsRetentionDays int = 30

// =============================================================================
// API MANAGEMENT PARAMETERS
// =============================================================================

@description('APIM publisher email')
param apimPublisherEmail string = ''

@description('APIM publisher name')
param apimPublisherName string = ''

@description('APIM SKU (Developer, Basic, Standard, Premium)')
param apimSku string = 'Developer'

// =============================================================================
// FRONT DOOR PARAMETERS
// =============================================================================

@description('Enable WAF for Front Door')
param frontDoorEnableWaf bool = false

// =============================================================================
// REDIS PARAMETERS
// =============================================================================

@description('Redis SKU (Basic, Standard, Premium)')
param redisSku string = 'Standard'

@description('Redis capacity')
param redisCapacity int = 1

// =============================================================================
// POLICY PARAMETERS
// =============================================================================

@description('Required tags for Azure Policy enforcement')
param requiredTags array = ['reason', 'purpose']

@description('Policy enforcement mode (Default = Deny, DoNotEnforce = Audit)')
param policyEnforcementMode string = 'Default'

// =============================================================================
// VARIABLES FOR DETERMINISTIC NAMING
// =============================================================================

var namingPrefix = '${projectName}-${environment}'
var openAIName = '${namingPrefix}-openai'
var cosmosDBName = '${namingPrefix}-cosmos'
var dataLakeName = replace('${namingPrefix}datalake', '-', '')
var sqlServerName = '${namingPrefix}-sql'
var sqlDatabaseName = '${namingPrefix}-sqldb'
var aiSearchName = '${namingPrefix}-search'
var containerAppsEnvName = '${namingPrefix}-containerapps-env'
var containerRegistryName = replace('${namingPrefix}acr', '-', '')
var keyVaultName = '${namingPrefix}-kv'
var logAnalyticsName = '${namingPrefix}-logs'
var appInsightsName = '${namingPrefix}-appinsights'
var vnetName = '${namingPrefix}-vnet'
var apimName = '${namingPrefix}-apim'
var frontDoorName = '${namingPrefix}-fd'
var wafPolicyName = '${namingPrefix}-waf'
var redisName = '${namingPrefix}-redis'

// Managed Identity names
var containerAppsMIName = '${namingPrefix}-containerapp-mi'

// Deploy networking if enabled
module networking './modules/networking.bicep' = if (enableVNet) {
  name: 'networking-deployment'
  params: {
    location: location
    vnetName: vnetName
    vnetAddressPrefix: vnetAddressPrefix
    containerAppsSubnetPrefix: containerAppsSubnetPrefix
    privateEndpointSubnetPrefix: privateEndpointSubnetPrefix
    sqlSubnetPrefix: sqlSubnetPrefix
    tags: tags
  }
}

// Deploy monitoring infrastructure
module monitoring './modules/monitoring.bicep' = if (enableMonitoring) {
  name: 'monitoring-deployment'
  params: {
    location: location
    logAnalyticsName: logAnalyticsName
    appInsightsName: appInsightsName
    retentionInDays: logAnalyticsRetentionDays
    tags: tags
  }
}

// Deploy managed identities
module identities './modules/identities.bicep' = {
  name: 'identities-deployment'
  params: {
    location: location
    containerAppsMIName: containerAppsMIName
    tags: tags
  }
}

// Deploy Key Vault
module keyVault './modules/keyvault.bicep' = if (enableKeyVault) {
  name: 'keyvault-deployment'
  params: {
    location: location
    keyVaultName: keyVaultName
    enableVNet: enableVNet
    privateEndpointSubnetId: enableVNet ? networking.outputs.privateEndpointSubnetId : ''
    vnetId: enableVNet ? networking.outputs.vnetId : ''
    containerAppsMIObjectId: identities.outputs.containerAppsMIObjectId
    skuName: keyVaultSku
    softDeleteRetentionInDays: keyVaultSoftDeleteRetentionDays
    tags: tags
  }
}

// Deploy OpenAI Service
module openAI './modules/openai.bicep' = if (enableOpenAI) {
  name: 'openai-deployment'
  params: {
    location: location
    openAIName: openAIName
    deployments: openAIDeployments
    enableVNet: enableVNet
    privateEndpointSubnetId: enableVNet ? networking.outputs.privateEndpointSubnetId : ''
    vnetId: enableVNet ? networking.outputs.vnetId : ''
    containerAppsMIObjectId: identities.outputs.containerAppsMIObjectId
    contentFilterPolicyName: openAIContentFilterPolicy
    tags: tags
  }
}

// Deploy Cosmos DB
module cosmosDB './modules/cosmosdb.bicep' = if (enableCosmosDB) {
  name: 'cosmosdb-deployment'
  params: {
    location: location
    cosmosDBName: cosmosDBName
    enableNoSQL: cosmosEnableNoSQL
    enableGremlin: cosmosEnableGremlin
    consistencyLevel: cosmosConsistencyLevel
    enableServerless: cosmosEnableServerless
    enableAnalyticalStorage: cosmosEnableAnalyticalStorage
    additionalLocations: cosmosAdditionalRegions
    enableVNet: enableVNet
    privateEndpointSubnetId: enableVNet ? networking.outputs.privateEndpointSubnetId : ''
    vnetId: enableVNet ? networking.outputs.vnetId : ''
    containerAppsMIObjectId: identities.outputs.containerAppsMIObjectId
    tags: tags
  }
}

// Deploy Data Lake Storage
module dataLake './modules/datalake.bicep' = if (enableDataLake) {
  name: 'datalake-deployment'
  params: {
    location: location
    dataLakeName: dataLakeName
    sku: dataLakeSku
    enableVNet: enableVNet
    privateEndpointSubnetId: enableVNet ? networking.outputs.privateEndpointSubnetId : ''
    vnetId: enableVNet ? networking.outputs.vnetId : ''
    containerAppsMIObjectId: identities.outputs.containerAppsMIObjectId
    tags: tags
  }
}
    tags: tags
  }
}

// Deploy SQL Database
module sqlDB './modules/sqldb.bicep' = if (enableSQLDB) {
  name: 'sqldb-deployment'
  params: {
    location: location
    sqlServerName: sqlServerName
    sqlDatabaseName: sqlDatabaseName
    sqlAdminUsername: sqlAdminUsername
    databaseSku: sqlDatabaseSku
    enableVNet: enableVNet
    privateEndpointSubnetId: enableVNet ? networking.outputs.privateEndpointSubnetId : ''
    vnetId: enableVNet ? networking.outputs.vnetId : ''
    containerAppsMIObjectId: identities.outputs.containerAppsMIObjectId
    containerAppsMIPrincipalId: identities.outputs.containerAppsMIPrincipalId
    allowedIpRanges: sqlAllowedIpRanges
    keyVaultName: enableKeyVault ? keyVaultName : ''
    zoneRedundant: sqlZoneRedundant
    tags: tags
  }
  dependsOn: [
    keyVault
  ]
}

// Deploy AI Search
module aiSearch './modules/aisearch.bicep' = if (enableAISearch) {
  name: 'aisearch-deployment'
  params: {
    location: location
    aiSearchName: aiSearchName
    sku: aiSearchSku
    replicaCount: aiSearchReplicaCount
    partitionCount: aiSearchPartitionCount
    semanticSearchTier: aiSearchSemanticTier
    enableVNet: enableVNet
    privateEndpointSubnetId: enableVNet ? networking.outputs.privateEndpointSubnetId : ''
    vnetId: enableVNet ? networking.outputs.vnetId : ''
    containerAppsMIObjectId: identities.outputs.containerAppsMIObjectId
    tags: tags
  }
}

// Deploy Container Registry
module containerRegistry './modules/containerregistry.bicep' = if (enableContainerRegistry) {
  name: 'containerregistry-deployment'
  params: {
    location: location
    containerRegistryName: containerRegistryName
    sku: containerRegistrySku
    enableVNet: enableVNet
    privateEndpointSubnetId: enableVNet ? networking.outputs.privateEndpointSubnetId : ''
    vnetId: enableVNet ? networking.outputs.vnetId : ''
    containerAppsMIObjectId: identities.outputs.containerAppsMIObjectId
    geoReplicationLocations: containerRegistryGeoReplicationLocations
    tags: tags
  }
}

// Deploy Container Apps Environment
module containerApps './modules/containerapps.bicep' = if (enableContainerApps) {
  name: 'containerapps-deployment'
  params: {
    location: location
    containerAppsEnvName: containerAppsEnvName
    enableVNet: enableVNet
    containerAppsSubnetId: enableVNet ? networking.outputs.containerAppsSubnetId : ''
    logAnalyticsWorkspaceId: enableMonitoring ? monitoring.outputs.logAnalyticsWorkspaceId : ''
    enableDapr: containerAppsEnableDapr
    enableZoneRedundancy: containerAppsZoneRedundant
    customDomainConfig: containerAppsCustomDomain
    tags: tags
  }
}

// Deploy RBAC assignments for admin users
module rbac './modules/rbac.bicep' = {
  name: 'rbac-deployment'
  params: {
    adminObjectIds: adminObjectIds
    openAIName: enableOpenAI ? openAIName : ''
    cosmosDBName: enableCosmosDB ? cosmosDBName : ''
    dataLakeName: enableDataLake ? dataLakeName : ''
    sqlServerName: enableSQLDB ? sqlServerName : ''
    aiSearchName: enableAISearch ? aiSearchName : ''
    containerRegistryName: enableContainerRegistry ? containerRegistryName : ''
    keyVaultName: enableKeyVault ? keyVaultName : ''
  }
  dependsOn: [
    openAI
    cosmosDB
    dataLake
    sqlDB
    aiSearch
    containerRegistry
    keyVault
  ]
}

// Deploy API Management
module apim './modules/apim.bicep' = if (enableAPIM) {
  name: 'apim-deployment'
  params: {
    location: location
    apimName: apimName
    publisherEmail: apimPublisherEmail
    publisherName: apimPublisherName
    sku: apimSku
    enableVNet: enableVNet
    privateEndpointSubnetId: enableVNet ? networking.outputs.privateEndpointSubnetId : ''
    vnetId: enableVNet ? networking.outputs.vnetId : ''
    openAIEndpoint: enableOpenAI ? openAI.outputs.endpoint : ''
    aiSearchEndpoint: enableAISearch ? aiSearch.outputs.endpoint : ''
    containerAppsMIObjectId: identities.outputs.containerAppsMIObjectId
    tags: tags
  }
}

// Deploy Azure Front Door
module frontDoor './modules/frontdoor.bicep' = if (enableFrontDoor) {
  name: 'frontdoor-deployment'
  params: {
    frontDoorName: frontDoorName
    wafPolicyName: wafPolicyName
    enableWaf: frontDoorEnableWaf
    containerAppsDefaultDomain: enableContainerApps ? containerApps.outputs.defaultDomain : ''
    apimGatewayHostname: enableAPIM ? '${apimName}.azure-api.net' : ''
    tags: tags
  }
}

// Deploy Redis Cache
module redis './modules/redis.bicep' = if (enableRedis) {
  name: 'redis-deployment'
  params: {
    location: location
    redisName: redisName
    sku: redisSku
    skuCapacity: redisCapacity
    enableVNet: enableVNet
    privateEndpointSubnetId: enableVNet ? networking.outputs.privateEndpointSubnetId : ''
    vnetId: enableVNet ? networking.outputs.vnetId : ''
    containerAppsMIObjectId: identities.outputs.containerAppsMIObjectId
    tags: tags
  }
}

// Deploy Azure Policy
module policy './modules/policy.bicep' = if (enablePolicy) {
  name: 'policy-deployment'
  params: {
    requiredTags: requiredTags
    enforcementMode: policyEnforcementMode
  }
}

// Outputs
output vnetId string = enableVNet ? networking.outputs.vnetId : ''
output containerAppsMIPrincipalId string = identities.outputs.containerAppsMIPrincipalId
output containerAppsMIClientId string = identities.outputs.containerAppsMIClientId
output openAIEndpoint string = enableOpenAI ? openAI.outputs.endpoint : ''
output cosmosDBEndpoint string = enableCosmosDB ? cosmosDB.outputs.endpoint : ''
output dataLakePrimaryEndpoint string = enableDataLake ? dataLake.outputs.primaryEndpoint : ''
output sqlServerFQDN string = enableSQLDB ? sqlDB.outputs.serverFQDN : ''
output aiSearchEndpoint string = enableAISearch ? aiSearch.outputs.endpoint : ''
output containerRegistryLoginServer string = enableContainerRegistry ? containerRegistry.outputs.loginServer : ''
output containerAppsEnvId string = enableContainerApps ? containerApps.outputs.environmentId : ''
output containerAppsDefaultDomain string = enableContainerApps ? containerApps.outputs.defaultDomain : ''
output keyVaultUri string = enableKeyVault ? keyVault.outputs.vaultUri : ''
output logAnalyticsWorkspaceId string = enableMonitoring ? monitoring.outputs.logAnalyticsWorkspaceId : ''
output apimGatewayUrl string = enableAPIM ? apim.outputs.gatewayUrl : ''
output frontDoorEndpoint string = enableFrontDoor ? frontDoor.outputs.frontDoorFqdn : ''
output redisHostName string = enableRedis ? redis.outputs.hostName : ''
