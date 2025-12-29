// Azure Redis Cache module

param location string
param redisName string
param sku string = 'Standard'
param skuFamily string = 'C'
param skuCapacity int = 1
param enableVNet bool
param privateEndpointSubnetId string = ''
param vnetId string = ''
param containerAppsMIObjectId string = ''
param enableNonSslPort bool = false
param minimumTlsVersion string = '1.2'
param tags object = {}

// Redis Cache
resource redis 'Microsoft.Cache/redis@2024-03-01' = {
  name: redisName
  location: location
  tags: tags
  properties: {
    sku: {
      name: sku
      family: skuFamily
      capacity: skuCapacity
    }
    enableNonSslPort: enableNonSslPort
    minimumTlsVersion: minimumTlsVersion
    publicNetworkAccess: enableVNet ? 'Disabled' : 'Enabled'
    redisConfiguration: {
      'maxmemory-policy': 'volatile-lru'
    }
  }
}

// Private Endpoint for Redis (if VNet enabled)
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-05-01' = if (enableVNet) {
  name: '${redisName}-pe'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${redisName}-pe-connection'
        properties: {
          privateLinkServiceId: redis.id
          groupIds: [
            'redisCache'
          ]
        }
      }
    ]
  }
}

// Private DNS Zone for Redis
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (enableVNet) {
  name: 'privatelink.redis.cache.windows.net'
  location: 'global'
  tags: tags
}

// VNet Link for Private DNS Zone
resource privateDnsZoneVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (enableVNet) {
  parent: privateDnsZone
  name: '${redisName}-vnet-link'
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
        name: 'privatelink-redis-cache-windows-net'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}

// RBAC: Grant Container Apps MI access to Redis
resource redisDataContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (containerAppsMIObjectId != '') {
  name: guid(redis.id, containerAppsMIObjectId, 'Redis Cache Contributor')
  scope: redis
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'e0f68234-74aa-48ed-b826-c38b57376e17') // Redis Cache Contributor
    principalId: containerAppsMIObjectId
    principalType: 'ServicePrincipal'
  }
}

output redisId string = redis.id
output redisName string = redis.name
output hostName string = redis.properties.hostName
output sslPort int = redis.properties.sslPort
output primaryKey string = redis.listKeys().primaryKey
