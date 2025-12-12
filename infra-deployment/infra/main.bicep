// Main Bicep orchestration file for Azure AI Landing Zone
// This file orchestrates the deployment of all infrastructure components

targetScope = 'resourceGroup'

// Parameters loaded from config
@description('Project name prefix for resource naming')
param projectName string

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Environment (dev, staging, prod)')
param environment string

@description('Admin user emails for RBAC assignments')
param adminEmails array = []

@description('Tags to apply to all resources')
param tags object = {}

// Networking parameters
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

// Service enablement flags
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

// Service-specific parameters
@description('OpenAI deployments configuration')
param openAIDeployments array = []

@description('Cosmos DB - Enable NoSQL API')
param cosmosEnableNoSQL bool = true

@description('Cosmos DB - Enable Gremlin API')
param cosmosEnableGremlin bool = true

@description('Cosmos DB - Consistency level')
param cosmosConsistencyLevel string = 'Session'

@description('SQL Database SKU')
param sqlDatabaseSku string = 'S1'

@description('SQL Admin Username')
param sqlAdminUsername string = 'sqladmin'

@description('SQL allowed IP ranges (CIDR notation)')
param sqlAllowedIpRanges array = []

@description('AI Search SKU')
param aiSearchSku string = 'standard'

@description('Container Registry SKU')
param containerRegistrySku string = 'Premium'

@description('Data Lake Storage SKU')
param dataLakeSku string = 'Standard_LRS'

// Variables for deterministic naming
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
    containerAppsMIObjectId: identities.outputs.containerAppsMIObjectId
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
    containerAppsMIObjectId: identities.outputs.containerAppsMIObjectId
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
    enableVNet: enableVNet
    privateEndpointSubnetId: enableVNet ? networking.outputs.privateEndpointSubnetId : ''
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
    containerAppsMIObjectId: identities.outputs.containerAppsMIObjectId
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
    containerAppsMIObjectId: identities.outputs.containerAppsMIObjectId
    containerAppsMIPrincipalId: identities.outputs.containerAppsMIPrincipalId
    allowedIpRanges: sqlAllowedIpRanges
    tags: tags
  }
}

// Deploy AI Search
module aiSearch './modules/aisearch.bicep' = if (enableAISearch) {
  name: 'aisearch-deployment'
  params: {
    location: location
    aiSearchName: aiSearchName
    sku: aiSearchSku
    enableVNet: enableVNet
    privateEndpointSubnetId: enableVNet ? networking.outputs.privateEndpointSubnetId : ''
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
    containerAppsMIObjectId: identities.outputs.containerAppsMIObjectId
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
    tags: tags
  }
}

// Deploy RBAC assignments for admin users
module rbac './modules/rbac.bicep' = {
  name: 'rbac-deployment'
  params: {
    adminEmails: adminEmails
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
output keyVaultUri string = enableKeyVault ? keyVault.outputs.vaultUri : ''
output logAnalyticsWorkspaceId string = enableMonitoring ? monitoring.outputs.logAnalyticsWorkspaceId : ''
