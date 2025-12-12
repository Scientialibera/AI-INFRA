// Azure AI Search module

param location string
param aiSearchName string
param sku string
param enableVNet bool
param privateEndpointSubnetId string
param containerAppsMIObjectId string
param tags object = {}

// Azure AI Search Service
resource aiSearch 'Microsoft.Search/searchServices@2023-11-01' = {
  name: aiSearchName
  location: location
  tags: tags
  sku: {
    name: sku
  }
  properties: {
    replicaCount: 1
    partitionCount: 1
    hostingMode: 'default'
    publicNetworkAccess: enableVNet ? 'disabled' : 'enabled'
    networkRuleSet: enableVNet ? {
      bypass: 'AzurePortal'
      ipRules: []
    } : null
    authOptions: {
      aadOrApiKey: {
        aadAuthFailureMode: 'http401WithBearerChallenge'
      }
    }
    semanticSearch: 'free'
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// Private Endpoint for AI Search (if VNet enabled)
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-05-01' = if (enableVNet) {
  name: '${aiSearchName}-pe'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${aiSearchName}-pe-connection'
        properties: {
          privateLinkServiceId: aiSearch.id
          groupIds: [
            'searchService'
          ]
        }
      }
    ]
  }
}

// Private DNS Zone for AI Search
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (enableVNet) {
  name: 'privatelink.search.windows.net'
  location: 'global'
  tags: tags
}

// Private DNS Zone Group
resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-05-01' = if (enableVNet) {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-search-windows-net'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}

// RBAC: Grant Container Apps MI access to AI Search - Search Index Data Contributor
resource searchIndexDataContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aiSearch.id, containerAppsMIObjectId, 'Search Index Data Contributor')
  scope: aiSearch
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8ebe5a00-799e-43f5-93ac-243d3dce84a7') // Search Index Data Contributor
    principalId: containerAppsMIObjectId
    principalType: 'ServicePrincipal'
  }
}

// RBAC: Grant Container Apps MI access to AI Search - Search Service Contributor
resource searchServiceContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aiSearch.id, containerAppsMIObjectId, 'Search Service Contributor')
  scope: aiSearch
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7ca78c08-252a-4471-8644-bb5ff32d4ba0') // Search Service Contributor
    principalId: containerAppsMIObjectId
    principalType: 'ServicePrincipal'
  }
}

output aiSearchId string = aiSearch.id
output endpoint string = 'https://${aiSearch.name}.search.windows.net'
output aiSearchName string = aiSearch.name
