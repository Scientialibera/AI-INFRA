// RBAC module - Assigns admin users to all services

param adminEmails array
param openAIName string
param cosmosDBName string
param dataLakeName string
param sqlServerName string
param aiSearchName string
param containerRegistryName string
param keyVaultName string

// Get references to existing resources
resource openAI 'Microsoft.CognitiveServices/accounts@2023-05-01' existing = if (openAIName != '') {
  name: openAIName
}

resource cosmosDB 'Microsoft.DocumentDB/databaseAccounts@2023-04-15' existing = if (cosmosDBName != '') {
  name: cosmosDBName
}

resource dataLake 'Microsoft.Storage/storageAccounts@2023-01-01' existing = if (dataLakeName != '') {
  name: dataLakeName
}

resource sqlServer 'Microsoft.Sql/servers@2023-05-01-preview' existing = if (sqlServerName != '') {
  name: sqlServerName
}

resource aiSearch 'Microsoft.Search/searchServices@2023-11-01' existing = if (aiSearchName != '') {
  name: aiSearchName
}

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = if (containerRegistryName != '') {
  name: containerRegistryName
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' existing = if (keyVaultName != '') {
  name: keyVaultName
}

// Role definitions
var cognitiveServicesOpenAIContributor = 'a001fd3d-188f-4b5d-821b-7da978bf7442'
var cosmosDBAccountContributor = '5bd9cd88-fe45-4216-938b-f97437e15450'
var cosmosDBDataContributor = '00000000-0000-0000-0000-000000000002'
var storageBlobDataOwner = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
var sqlDBContributor = '9b7fa17d-e63e-47b0-bb0a-15c516ac86ec'
var sqlSecurityManager = '056cd41c-7e88-42e1-933e-88ba6a50c9c3'
var searchServiceContributor = '7ca78c08-252a-4471-8644-bb5ff32d4ba0'
var searchIndexDataContributor = '8ebe5a00-799e-43f5-93ac-243d3dce84a7'
var acrPush = '8311e382-0749-4cb8-b61a-304f252e45ec'
var keyVaultAdministrator = '00482a5a-887f-4fb3-b233-3c3c4e4e8e12'
var contributor = 'b24988ac-6180-42a0-ab88-20f7382dd24c'

// Assign roles to each admin user for OpenAI
resource openAIAdminRoles 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (email, i) in adminEmails: if (openAIName != '') {
  name: guid(openAI.id, email, 'OpenAI Contributor')
  scope: openAI
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesOpenAIContributor)
    principalId: email
    principalType: 'User'
  }
}]

// Assign roles to each admin user for Cosmos DB
resource cosmosDBAdminRolesContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (email, i) in adminEmails: if (cosmosDBName != '') {
  name: guid(cosmosDB.id, email, 'Cosmos DB Account Contributor')
  scope: cosmosDB
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cosmosDBAccountContributor)
    principalId: email
    principalType: 'User'
  }
}]

resource cosmosDBAdminRolesData 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (email, i) in adminEmails: if (cosmosDBName != '') {
  name: guid(cosmosDB.id, email, 'Cosmos DB Data Contributor')
  scope: cosmosDB
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cosmosDBDataContributor)
    principalId: email
    principalType: 'User'
  }
}]

// Assign roles to each admin user for Data Lake
resource dataLakeAdminRoles 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (email, i) in adminEmails: if (dataLakeName != '') {
  name: guid(dataLake.id, email, 'Storage Blob Data Owner')
  scope: dataLake
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataOwner)
    principalId: email
    principalType: 'User'
  }
}]

// Assign roles to each admin user for SQL Server
resource sqlServerAdminRolesContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (email, i) in adminEmails: if (sqlServerName != '') {
  name: guid(sqlServer.id, email, 'SQL DB Contributor')
  scope: sqlServer
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', sqlDBContributor)
    principalId: email
    principalType: 'User'
  }
}]

resource sqlServerAdminRolesSecurity 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (email, i) in adminEmails: if (sqlServerName != '') {
  name: guid(sqlServer.id, email, 'SQL Security Manager')
  scope: sqlServer
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', sqlSecurityManager)
    principalId: email
    principalType: 'User'
  }
}]

// Assign roles to each admin user for AI Search
resource aiSearchAdminRolesService 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (email, i) in adminEmails: if (aiSearchName != '') {
  name: guid(aiSearch.id, email, 'Search Service Contributor')
  scope: aiSearch
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', searchServiceContributor)
    principalId: email
    principalType: 'User'
  }
}]

resource aiSearchAdminRolesIndex 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (email, i) in adminEmails: if (aiSearchName != '') {
  name: guid(aiSearch.id, email, 'Search Index Data Contributor')
  scope: aiSearch
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', searchIndexDataContributor)
    principalId: email
    principalType: 'User'
  }
}]

// Assign roles to each admin user for Container Registry
resource acrAdminRoles 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (email, i) in adminEmails: if (containerRegistryName != '') {
  name: guid(containerRegistry.id, email, 'AcrPush')
  scope: containerRegistry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPush)
    principalId: email
    principalType: 'User'
  }
}]

// Assign roles to each admin user for Key Vault
resource keyVaultAdminRoles 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (email, i) in adminEmails: if (keyVaultName != '') {
  name: guid(keyVault.id, email, 'Key Vault Administrator')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultAdministrator)
    principalId: email
    principalType: 'User'
  }
}]

// Assign Contributor role at resource group level for overall management
resource rgAdminRoles 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (email, i) in adminEmails: {
  name: guid(resourceGroup().id, email, 'Contributor')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', contributor)
    principalId: email
    principalType: 'User'
  }
}]
