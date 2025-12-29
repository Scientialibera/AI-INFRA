// Cosmos DB module

param location string
param cosmosDBName string
param enableNoSQL bool
param enableGremlin bool
param consistencyLevel string
param enableVNet bool
param privateEndpointSubnetId string
param vnetId string = ''
param containerAppsMIObjectId string
param enableServerless bool = false
param enableAnalyticalStorage bool = false
param additionalLocations array = []
param tags object = {}

// Cosmos DB Account
resource cosmosDB 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' = {
  name: cosmosDBName
  location: location
  tags: tags
  kind: enableGremlin ? 'GlobalDocumentDB' : 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    consistencyPolicy: {
      defaultConsistencyLevel: consistencyLevel
    }
    locations: concat([
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ], [for (loc, i) in additionalLocations: {
      locationName: loc
      failoverPriority: i + 1
      isZoneRedundant: false
    }])
    capabilities: concat(
      enableGremlin ? [{ name: 'EnableGremlin' }] : [],
      enableServerless ? [{ name: 'EnableServerless' }] : []
    )
    enableAutomaticFailover: true
    enableMultipleWriteLocations: false
    enableAnalyticalStorage: enableAnalyticalStorage
    publicNetworkAccess: enableVNet ? 'Disabled' : 'Enabled'
    networkAclBypass: 'AzureServices'
  }
}

// NoSQL Database (if enabled)
resource sqlDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2023-04-15' = if (enableNoSQL) {
  parent: cosmosDB
  name: 'nosql-db'
  properties: {
    resource: {
      id: 'nosql-db'
    }
    options: {
      throughput: 400
    }
  }
}

// Default container for NoSQL
resource sqlContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-04-15' = if (enableNoSQL) {
  parent: sqlDatabase
  name: 'default-container'
  properties: {
    resource: {
      id: 'default-container'
      partitionKey: {
        paths: [
          '/id'
        ]
        kind: 'Hash'
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        automatic: true
        includedPaths: [
          {
            path: '/*'
          }
        ]
      }
    }
  }
}

// Gremlin Database (if enabled)
resource gremlinDatabase 'Microsoft.DocumentDB/databaseAccounts/gremlinDatabases@2023-04-15' = if (enableGremlin) {
  parent: cosmosDB
  name: 'graph-db'
  properties: {
    resource: {
      id: 'graph-db'
    }
    options: {
      throughput: 400
    }
  }
}

// Default graph for Gremlin
resource gremlinGraph 'Microsoft.DocumentDB/databaseAccounts/gremlinDatabases/graphs@2023-04-15' = if (enableGremlin) {
  parent: gremlinDatabase
  name: 'default-graph'
  properties: {
    resource: {
      id: 'default-graph'
      partitionKey: {
        paths: [
          '/partitionKey'
        ]
        kind: 'Hash'
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        automatic: true
      }
    }
  }
}

// Private Endpoint for Cosmos DB (if VNet enabled)
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-05-01' = if (enableVNet) {
  name: '${cosmosDBName}-pe'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${cosmosDBName}-pe-connection'
        properties: {
          privateLinkServiceId: cosmosDB.id
          groupIds: [
            'Sql'
          ]
        }
      }
    ]
  }
}

// Private DNS Zone for Cosmos DB
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (enableVNet) {
  name: 'privatelink.documents.azure.com'
  location: 'global'
  tags: tags
}

// VNet Link for Private DNS Zone
resource privateDnsZoneVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (enableVNet) {
  parent: privateDnsZone
  name: '${cosmosDBName}-vnet-link'
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
        name: 'privatelink-documents-azure-com'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}

// RBAC: Grant Container Apps MI access to Cosmos DB using SQL Role Assignment (data plane)
// Built-in Cosmos DB Data Contributor role
var cosmosDataContributorRoleId = '00000000-0000-0000-0000-000000000002'

resource cosmosDBSqlRoleAssignment 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-05-15' = {
  parent: cosmosDB
  name: guid(cosmosDB.id, containerAppsMIObjectId, cosmosDataContributorRoleId)
  properties: {
    roleDefinitionId: '${cosmosDB.id}/sqlRoleDefinitions/${cosmosDataContributorRoleId}'
    principalId: containerAppsMIObjectId
    scope: cosmosDB.id
  }
}

output cosmosDBId string = cosmosDB.id
output endpoint string = cosmosDB.properties.documentEndpoint
output cosmosDBName string = cosmosDB.name
