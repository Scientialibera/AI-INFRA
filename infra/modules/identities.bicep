// Managed Identities module

param location string
param containerAppsMIName string
param tags object = {}

// Managed Identity for Container Apps
resource containerAppsMI 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: containerAppsMIName
  location: location
  tags: tags
}

output containerAppsMIObjectId string = containerAppsMI.properties.principalId
output containerAppsMIPrincipalId string = containerAppsMI.properties.principalId
output containerAppsMIClientId string = containerAppsMI.properties.clientId
output containerAppsMIId string = containerAppsMI.id
