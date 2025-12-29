// Data Lake Storage Gen2 module

param location string
param dataLakeName string
param sku string
param enableVNet bool
param privateEndpointSubnetId string
param vnetId string = ''
param containerAppsMIObjectId string
param tags object = {}

// Storage Account with hierarchical namespace (Data Lake Gen2)
resource dataLake 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: dataLakeName
  location: location
  tags: tags
  sku: {
    name: sku
  }
  kind: 'StorageV2'
  properties: {
    isHnsEnabled: true // Hierarchical namespace for Data Lake Gen2
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    networkAcls: enableVNet ? {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      virtualNetworkRules: []
      ipRules: []
    } : {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
    encryption: {
      services: {
        blob: {
          enabled: true
        }
        file: {
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
  }
}

// Blob Service
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: dataLake
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

// Default container
resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: 'data'
  properties: {
    publicAccess: 'None'
  }
}

// Private Endpoint for Blob (if VNet enabled)
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-05-01' = if (enableVNet) {
  name: '${dataLakeName}-blob-pe'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${dataLakeName}-blob-pe-connection'
        properties: {
          privateLinkServiceId: dataLake.id
          groupIds: [
            'blob'
          ]
        }
      }
    ]
  }
}

// Private Endpoint for DFS (Data Lake) (if VNet enabled)
resource privateEndpointDfs 'Microsoft.Network/privateEndpoints@2023-05-01' = if (enableVNet) {
  name: '${dataLakeName}-dfs-pe'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${dataLakeName}-dfs-pe-connection'
        properties: {
          privateLinkServiceId: dataLake.id
          groupIds: [
            'dfs'
          ]
        }
      }
    ]
  }
}

// Private DNS Zone for Blob
resource privateDnsZoneBlob 'Microsoft.Network/privateDnsZones@2020-06-01' = if (enableVNet) {
  name: 'privatelink.blob.core.windows.net'
  location: 'global'
  tags: tags
}

// VNet Link for Blob Private DNS Zone
resource privateDnsZoneVnetLinkBlob 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (enableVNet) {
  parent: privateDnsZoneBlob
  name: '${dataLakeName}-blob-vnet-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

// Private DNS Zone for DFS
resource privateDnsZoneDfs 'Microsoft.Network/privateDnsZones@2020-06-01' = if (enableVNet) {
  name: 'privatelink.dfs.core.windows.net'
  location: 'global'
  tags: tags
}

// VNet Link for DFS Private DNS Zone
resource privateDnsZoneVnetLinkDfs 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (enableVNet) {
  parent: privateDnsZoneDfs
  name: '${dataLakeName}-dfs-vnet-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

// Private DNS Zone Group for Blob
resource privateDnsZoneGroupBlob 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-05-01' = if (enableVNet) {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-blob-core-windows-net'
        properties: {
          privateDnsZoneId: privateDnsZoneBlob.id
        }
      }
    ]
  }
}

// Private DNS Zone Group for DFS
resource privateDnsZoneGroupDfs 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-05-01' = if (enableVNet) {
  parent: privateEndpointDfs
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-dfs-core-windows-net'
        properties: {
          privateDnsZoneId: privateDnsZoneDfs.id
        }
      }
    ]
  }
}

// RBAC: Grant Container Apps MI access to Data Lake
resource storageBlobDataContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(dataLake.id, containerAppsMIObjectId, 'Storage Blob Data Contributor')
  scope: dataLake
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: containerAppsMIObjectId
    principalType: 'ServicePrincipal'
  }
}

output dataLakeId string = dataLake.id
output primaryEndpoint string = dataLake.properties.primaryEndpoints.blob
output dfsEndpoint string = dataLake.properties.primaryEndpoints.dfs
output dataLakeName string = dataLake.name
