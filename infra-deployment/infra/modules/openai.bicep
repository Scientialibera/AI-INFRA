// OpenAI Service module

param location string
param openAIName string
param deployments array = []
param enableVNet bool
param privateEndpointSubnetId string
param vnetId string = ''
param containerAppsMIObjectId string
param contentFilterPolicyName string = 'default'
param tags object = {}

// OpenAI Cognitive Services Account
resource openAI 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: openAIName
  location: location
  tags: tags
  kind: 'OpenAI'
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: openAIName
    publicNetworkAccess: enableVNet ? 'Disabled' : 'Enabled'
    networkAcls: enableVNet ? {
      defaultAction: 'Deny'
      virtualNetworkRules: []
      ipRules: []
    } : {
      defaultAction: 'Allow'
    }
  }
}

// Deploy models
@batchSize(1)
resource openAIDeployments 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = [for deployment in deployments: {
  parent: openAI
  name: deployment.name
  sku: {
    name: 'Standard'
    capacity: deployment.capacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: deployment.model
      version: deployment.version
    }
    raiPolicyName: contains(deployment, 'raiPolicyName') ? deployment.raiPolicyName : contentFilterPolicyName
  }
}]

// Private Endpoint for OpenAI (if VNet enabled)
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-05-01' = if (enableVNet) {
  name: '${openAIName}-pe'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${openAIName}-pe-connection'
        properties: {
          privateLinkServiceId: openAI.id
          groupIds: [
            'account'
          ]
        }
      }
    ]
  }
}

// Private DNS Zone for OpenAI
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (enableVNet) {
  name: 'privatelink.openai.azure.com'
  location: 'global'
  tags: tags
}

// VNet Link for Private DNS Zone
resource privateDnsZoneVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (enableVNet) {
  parent: privateDnsZone
  name: '${openAIName}-vnet-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

// Private DNS Zone Group
resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-05-01' = if (enableVNet) {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-openai-azure-com'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}

// RBAC: Grant Container Apps MI access to OpenAI
resource openAIUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(openAI.id, containerAppsMIObjectId, 'Cognitive Services OpenAI User')
  scope: openAI
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd') // Cognitive Services OpenAI User
    principalId: containerAppsMIObjectId
    principalType: 'ServicePrincipal'
  }
}

output openAIId string = openAI.id
output endpoint string = openAI.properties.endpoint
output openAIName string = openAI.name
