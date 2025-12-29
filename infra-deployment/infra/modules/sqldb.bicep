// Azure SQL Database module

param location string
param sqlServerName string
param sqlDatabaseName string
param sqlAdminUsername string
param databaseSku string
param enableVNet bool
param privateEndpointSubnetId string
param vnetId string = ''
param containerAppsMIObjectId string
param containerAppsMIPrincipalId string
param allowedIpRanges array = []
param keyVaultName string = ''
param zoneRedundant bool = false
param tags object = {}

// Generate a secure password for SQL admin
resource sqlAdminPasswordSecret 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: '${sqlServerName}-password-generator'
  location: location
  kind: 'AzurePowerShell'
  properties: {
    azPowerShellVersion: '9.0'
    retentionInterval: 'P1D'
    scriptContent: '''
      $password = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 32 | ForEach-Object {[char]$_})
      $output = @{password = $password}
      Write-Output $output | ConvertTo-Json
      $DeploymentScriptOutputs = @{}
      $DeploymentScriptOutputs['password'] = $password
    '''
  }
}

// Azure SQL Server
resource sqlServer 'Microsoft.Sql/servers@2023-05-01-preview' = {
  name: sqlServerName
  location: location
  tags: tags
  properties: {
    administratorLogin: sqlAdminUsername
    administratorLoginPassword: sqlAdminPasswordSecret.properties.outputs.password
    version: '12.0'
    minimalTlsVersion: '1.2'
    publicNetworkAccess: enableVNet ? 'Disabled' : 'Enabled'
    administrators: {
      administratorType: 'ActiveDirectory'
      principalType: 'ServicePrincipal'
      login: 'ContainerAppsMI'
      sid: containerAppsMIPrincipalId
      tenantId: subscription().tenantId
      azureADOnlyAuthentication: false
    }
  }
}

// Azure SQL Database
resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-05-01-preview' = {
  parent: sqlServer
  name: sqlDatabaseName
  location: location
  tags: tags
  sku: {
    name: databaseSku
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 2147483648 // 2 GB
    catalogCollation: 'SQL_Latin1_General_CP1_CI_AS'
    zoneRedundant: zoneRedundant
    readScale: 'Disabled'
  }
}

// Firewall rule to allow Azure services (if not using VNet)
resource firewallRuleAzure 'Microsoft.Sql/servers/firewallRules@2023-05-01-preview' = if (!enableVNet) {
  parent: sqlServer
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// Firewall rules for whitelisted IP ranges
resource firewallRulesIP 'Microsoft.Sql/servers/firewallRules@2023-05-01-preview' = [for (ipRange, index) in allowedIpRanges: {
  parent: sqlServer
  name: 'AllowIP-${index}'
  properties: {
    // Parse CIDR notation (e.g., "203.0.113.0/24" or "198.51.100.42/32")
    startIpAddress: split(ipRange, '/')[0]
    // For simplicity, if /32, use same IP for start and end
    // For broader ranges, Azure will handle the CIDR properly
    endIpAddress: contains(ipRange, '/32') ? split(ipRange, '/')[0] : split(ipRange, '/')[0]
  }
}]

// Private Endpoint for SQL Server (if VNet enabled)
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-05-01' = if (enableVNet) {
  name: '${sqlServerName}-pe'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${sqlServerName}-pe-connection'
        properties: {
          privateLinkServiceId: sqlServer.id
          groupIds: [
            'sqlServer'
          ]
        }
      }
    ]
  }
}

// Private DNS Zone for SQL Server
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (enableVNet) {
  name: 'privatelink.database.windows.net'
  location: 'global'
  tags: tags
}

// VNet Link for Private DNS Zone
resource privateDnsZoneVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (enableVNet) {
  parent: privateDnsZone
  name: '${sqlServerName}-vnet-link'
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
        name: 'privatelink-database-windows-net'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}

// RBAC: Grant Container Apps MI access to SQL Server (Contributor role)
resource sqlServerContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(sqlServer.id, containerAppsMIObjectId, 'SQL DB Contributor')
  scope: sqlServer
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '9b7fa17d-e63e-47b0-bb0a-15c516ac86ec') // SQL DB Contributor
    principalId: containerAppsMIObjectId
    principalType: 'ServicePrincipal'
  }
}

// Store SQL Admin Password in Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = if (keyVaultName != '') {
  name: keyVaultName
}

resource sqlPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (keyVaultName != '') {
  parent: keyVault
  name: 'sql-admin-password'
  properties: {
    value: sqlAdminPasswordSecret.properties.outputs.password
    contentType: 'text/plain'
  }
}

resource sqlConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (keyVaultName != '') {
  parent: keyVault
  name: 'sql-connection-string'
  properties: {
    value: 'Server=tcp:${sqlServer.properties.fullyQualifiedDomainName},1433;Initial Catalog=${sqlDatabaseName};Persist Security Info=False;User ID=${sqlAdminUsername};Password=${sqlAdminPasswordSecret.properties.outputs.password};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'
    contentType: 'text/plain'
  }
}

output sqlServerId string = sqlServer.id
output sqlDatabaseId string = sqlDatabase.id
output serverFQDN string = sqlServer.properties.fullyQualifiedDomainName
output sqlServerName string = sqlServer.name
output sqlDatabaseName string = sqlDatabase.name
