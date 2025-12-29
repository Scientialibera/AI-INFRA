// Azure Container Apps Environment module

param location string
param containerAppsEnvName string
param enableVNet bool
param containerAppsSubnetId string
param logAnalyticsWorkspaceId string
param enableDapr bool = false
param enableZoneRedundancy bool = false
param customDomainConfig object = {}
param tags object = {}

// Container Apps Environment
resource containerAppsEnv 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: containerAppsEnvName
  location: location
  tags: tags
  properties: {
    vnetConfiguration: enableVNet ? {
      infrastructureSubnetId: containerAppsSubnetId
      internal: false
    } : null
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: reference(logAnalyticsWorkspaceId, '2022-10-01').customerId
        sharedKey: listKeys(logAnalyticsWorkspaceId, '2022-10-01').primarySharedKey
      }
    }
    zoneRedundant: enableZoneRedundancy
    daprAIConnectionString: enableDapr ? '' : null
  }
}

// Custom Domain Certificate (if custom domain is configured)
resource customDomainCert 'Microsoft.App/managedEnvironments/certificates@2024-03-01' = if (!empty(customDomainConfig) && contains(customDomainConfig, 'certificateValue')) {
  parent: containerAppsEnv
  name: contains(customDomainConfig, 'certificateName') ? customDomainConfig.certificateName : 'custom-domain-cert'
  location: location
  properties: {
    value: customDomainConfig.certificateValue
    password: contains(customDomainConfig, 'certificatePassword') ? customDomainConfig.certificatePassword : ''
  }
}

// Dapr Component for State Store (if Dapr is enabled)
resource daprStateStore 'Microsoft.App/managedEnvironments/daprComponents@2024-03-01' = if (enableDapr) {
  parent: containerAppsEnv
  name: 'statestore'
  properties: {
    componentType: 'state.azure.cosmosdb'
    version: 'v1'
    ignoreErrors: false
    initTimeout: '5s'
    scopes: []
    metadata: []
  }
}

output environmentId string = containerAppsEnv.id
output environmentName string = containerAppsEnv.name
output defaultDomain string = containerAppsEnv.properties.defaultDomain
output staticIp string = containerAppsEnv.properties.staticIp
