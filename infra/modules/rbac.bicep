// RBAC module - Assigns admin users to all services
// NOTE: adminObjectIds should contain Azure AD Object IDs (GUIDs), not email addresses
// The deploy.ps1 script resolves emails to Object IDs before calling this module

@description('Array of Azure AD Object IDs for admin users (resolved from emails by deploy script)')
param adminObjectIds array

param openAIName string
param cosmosDBName string
param dataLakeName string
param sqlServerName string
param aiSearchName string
param containerRegistryName string
param keyVaultName string

// Get references to existing resources
resource openAI 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = if (openAIName != '') {
  name: openAIName
}

resource cosmosDB 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' existing = if (cosmosDBName != '') {
  name: cosmosDBName
}

resource dataLake 'Microsoft.Storage/storageAccounts@2023-01-01' existing = if (dataLakeName != '') {
  name: dataLakeName
}

resource sqlServer 'Microsoft.Sql/servers@2023-05-01-preview' existing = if (sqlServerName != '') {
  name: sqlServerName
}

resource aiSearch 'Microsoft.Search/searchServices@2024-06-01-preview' existing = if (aiSearchName != '') {
  name: aiSearchName
}

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = if (containerRegistryName != '') {
  name: containerRegistryName
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = if (keyVaultName != '') {
  name: keyVaultName
}

// Role definitions
var cognitiveServicesOpenAIContributor = 'a001fd3d-188f-4b5d-821b-7da978bf7442'
var cosmosDBAccountContributor = '5bd9cd88-fe45-4216-938b-f97437e15450'
var storageBlobDataOwner = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
var sqlDBContributor = '9b7fa17d-e63e-47b0-bb0a-15c516ac86ec'
var sqlSecurityManager = '056cd41c-7e88-42e1-933e-88ba6a50c9c3'
var searchServiceContributor = '7ca78c08-252a-4471-8644-bb5ff32d4ba0'
var searchIndexDataContributor = '8ebe5a00-799e-43f5-93ac-243d3dce84a7'
var acrPush = '8311e382-0749-4cb8-b61a-304f252e45ec'
var keyVaultAdministrator = '00482a5a-887f-4fb3-b233-3c3c4e4e8e12'
var contributor = 'b24988ac-6180-42a0-ab88-20f7382dd24c'

// Cosmos DB built-in data contributor role for SQL Role Assignment
var cosmosDataContributorRoleId = '00000000-0000-0000-0000-000000000002'

// Assign roles to each admin user for OpenAI
resource openAIAdminRoles 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (objectId, i) in adminObjectIds: if (openAIName != '') {
  name: guid(openAI.id, objectId, 'OpenAI Contributor')
  scope: openAI
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesOpenAIContributor)
    principalId: objectId
    principalType: 'User'
  }
}]

// Assign roles to each admin user for Cosmos DB (control plane)
resource cosmosDBAdminRolesContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (objectId, i) in adminObjectIds: if (cosmosDBName != '') {
  name: guid(cosmosDB.id, objectId, 'Cosmos DB Account Contributor')
  scope: cosmosDB
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cosmosDBAccountContributor)
    principalId: objectId
    principalType: 'User'
  }
}]

// Assign Cosmos DB data plane access using SQL Role Assignment
resource cosmosDBAdminDataRoles 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-05-15' = [for (objectId, i) in adminObjectIds: if (cosmosDBName != '') {
  parent: cosmosDB
  name: guid(cosmosDB.id, objectId, cosmosDataContributorRoleId)
  properties: {
    roleDefinitionId: '${cosmosDB.id}/sqlRoleDefinitions/${cosmosDataContributorRoleId}'
    principalId: objectId
    scope: cosmosDB.id
  }
}]

// Assign roles to each admin user for Data Lake
resource dataLakeAdminRoles 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (objectId, i) in adminObjectIds: if (dataLakeName != '') {
  name: guid(dataLake.id, objectId, 'Storage Blob Data Owner')
  scope: dataLake
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataOwner)
    principalId: objectId
    principalType: 'User'
  }
}]

// Assign roles to each admin user for SQL Server
resource sqlServerAdminRolesContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (objectId, i) in adminObjectIds: if (sqlServerName != '') {
  name: guid(sqlServer.id, objectId, 'SQL DB Contributor')
  scope: sqlServer
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', sqlDBContributor)
    principalId: objectId
    principalType: 'User'
  }
}]

resource sqlServerAdminRolesSecurity 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (objectId, i) in adminObjectIds: if (sqlServerName != '') {
  name: guid(sqlServer.id, objectId, 'SQL Security Manager')
  scope: sqlServer
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', sqlSecurityManager)
    principalId: objectId
    principalType: 'User'
  }
}]

// Assign roles to each admin user for AI Search
resource aiSearchAdminRolesService 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (objectId, i) in adminObjectIds: if (aiSearchName != '') {
  name: guid(aiSearch.id, objectId, 'Search Service Contributor')
  scope: aiSearch
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', searchServiceContributor)
    principalId: objectId
    principalType: 'User'
  }
}]

resource aiSearchAdminRolesIndex 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (objectId, i) in adminObjectIds: if (aiSearchName != '') {
  name: guid(aiSearch.id, objectId, 'Search Index Data Contributor')
  scope: aiSearch
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', searchIndexDataContributor)
    principalId: objectId
    principalType: 'User'
  }
}]

// Assign roles to each admin user for Container Registry
resource acrAdminRoles 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (objectId, i) in adminObjectIds: if (containerRegistryName != '') {
  name: guid(containerRegistry.id, objectId, 'AcrPush')
  scope: containerRegistry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPush)
    principalId: objectId
    principalType: 'User'
  }
}]

// Assign roles to each admin user for Key Vault
resource keyVaultAdminRoles 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (objectId, i) in adminObjectIds: if (keyVaultName != '') {
  name: guid(keyVault.id, objectId, 'Key Vault Administrator')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultAdministrator)
    principalId: objectId
    principalType: 'User'
  }
}]

// Assign Contributor role at resource group level for overall management
resource rgAdminRoles 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (objectId, i) in adminObjectIds: {
  name: guid(resourceGroup().id, objectId, 'Contributor')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', contributor)
    principalId: objectId
    principalType: 'User'
  }
}]
