// Azure Container Registry module

param location string
param containerRegistryName string
param sku string
param enableVNet bool
param privateEndpointSubnetId string
param containerAppsMIObjectId string
param tags object = {}

// Azure Container Registry
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: containerRegistryName
  location: location
  tags: tags
  sku: {
    name: sku
  }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: enableVNet ? 'Disabled' : 'Enabled'
    networkRuleBypassOptions: 'AzureServices'
    zoneRedundancy: 'Disabled'
  }
}

// Private Endpoint for Container Registry (if VNet enabled and Premium SKU)
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-05-01' = if (enableVNet && sku == 'Premium') {
  name: '${containerRegistryName}-pe'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${containerRegistryName}-pe-connection'
        properties: {
          privateLinkServiceId: containerRegistry.id
          groupIds: [
            'registry'
          ]
        }
      }
    ]
  }
}

// Private DNS Zone for Container Registry
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (enableVNet && sku == 'Premium') {
  name: 'privatelink.azurecr.io'
  location: 'global'
  tags: tags
}

// Private DNS Zone Group
resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-05-01' = if (enableVNet && sku == 'Premium') {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-azurecr-io'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}

// RBAC: Grant Container Apps MI access to pull images from ACR
resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(containerRegistry.id, containerAppsMIObjectId, 'AcrPull')
  scope: containerRegistry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull
    principalId: containerAppsMIObjectId
    principalType: 'ServicePrincipal'
  }
}

output containerRegistryId string = containerRegistry.id
output loginServer string = containerRegistry.properties.loginServer
output containerRegistryName string = containerRegistry.name
