// Networking module - VNet, Subnets, NSGs

param location string
param vnetName string
param vnetAddressPrefix string
param containerAppsSubnetPrefix string
param privateEndpointSubnetPrefix string
param sqlSubnetPrefix string
param tags object = {}

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
    subnets: [
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
    ]
  }
}

// Network Security Group for Container Apps
resource containerAppsNSG 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
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
resource privateEndpointNSG 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: '${vnetName}-privateendpoint-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: []
  }
}

// Network Security Group for SQL
resource sqlNSG 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
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

output vnetId string = vnet.id
output vnetName string = vnet.name
output containerAppsSubnetId string = vnet.properties.subnets[0].id
output privateEndpointSubnetId string = vnet.properties.subnets[1].id
output sqlSubnetId string = vnet.properties.subnets[2].id
