// Networking module - VNet, Subnets, NSGs

param location string
param vnetName string
param vnetAddressPrefix string
param containerAppsSubnetPrefix string
param privateEndpointSubnetPrefix string
param sqlSubnetPrefix string
param apimSubnetPrefix string = '10.0.4.0/27'
param enableContainerAppsSubnet bool = false
param enablePrivateEndpointSubnet bool = false
param enableSqlSubnet bool = false
param enableApimSubnet bool = false
param tags object = {}

var subnets = concat(
  enableContainerAppsSubnet ? [
    {
      name: 'snet-containerapps'
      properties: {
        addressPrefix: containerAppsSubnetPrefix
        networkSecurityGroup: {
          id: containerAppsNSG.id
        }
        delegations: []
      }
    }
  ] : [],
  enablePrivateEndpointSubnet ? [
    {
      name: 'snet-privateendpoints'
      properties: {
        addressPrefix: privateEndpointSubnetPrefix
        networkSecurityGroup: {
          id: privateEndpointNSG.id
        }
        privateEndpointNetworkPolicies: 'Disabled'
      }
    }
  ] : [],
  enableSqlSubnet ? [
    {
      name: 'snet-sql'
      properties: {
        addressPrefix: sqlSubnetPrefix
        networkSecurityGroup: {
          id: sqlNSG.id
        }
        // Note: No delegation needed for Azure SQL Database
        // Delegation is only required for SQL Managed Instance
      }
    }
  ] : [],
  enableApimSubnet ? [
    {
      name: 'snet-apim'
      properties: {
        addressPrefix: apimSubnetPrefix
        networkSecurityGroup: {
          id: apimNSG.id
        }
      }
    }
  ] : []
)

// Virtual Network
resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: subnets
  }
}

// Network Security Group for Container Apps
resource containerAppsNSG 'Microsoft.Network/networkSecurityGroups@2023-05-01' = if (enableContainerAppsSubnet) {
  name: '${vnetName}-containerapps-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowHTTPSInbound'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowHTTPInbound'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
    ]
  }
}

// Network Security Group for Private Endpoints
resource privateEndpointNSG 'Microsoft.Network/networkSecurityGroups@2023-05-01' = if (enablePrivateEndpointSubnet) {
  name: '${vnetName}-privateendpoint-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: []
  }
}

// Network Security Group for SQL
resource sqlNSG 'Microsoft.Network/networkSecurityGroups@2023-05-01' = if (enableSqlSubnet) {
  name: '${vnetName}-sql-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowSQLInbound'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '1433'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
    ]
  }
}

// Network Security Group for APIM
resource apimNSG 'Microsoft.Network/networkSecurityGroups@2023-05-01' = if (enableApimSubnet) {
  name: '${vnetName}-apim-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: []
  }
}

output vnetId string = vnet.id
output vnetName string = vnet.name
output containerAppsSubnetId string = enableContainerAppsSubnet ? '${vnet.id}/subnets/snet-containerapps' : ''
output privateEndpointSubnetId string = enablePrivateEndpointSubnet ? '${vnet.id}/subnets/snet-privateendpoints' : ''
output sqlSubnetId string = enableSqlSubnet ? '${vnet.id}/subnets/snet-sql' : ''
output apimSubnetId string = enableApimSubnet ? '${vnet.id}/subnets/snet-apim' : ''
