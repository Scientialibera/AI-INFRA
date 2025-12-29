// Azure API Management module

param location string
param apimName string
param publisherEmail string
param publisherName string
param sku string = 'Developer'
param skuCount int = 1
param enableVNet bool
param privateEndpointSubnetId string = ''
param vnetId string = ''
param openAIEndpoint string = ''
param aiSearchEndpoint string = ''
param containerAppsMIObjectId string = ''
param tags object = {}

// API Management Service
resource apim 'Microsoft.ApiManagement/service@2023-09-01-preview' = {
  name: apimName
  location: location
  tags: tags
  sku: {
    name: sku
    capacity: skuCount
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    virtualNetworkType: enableVNet ? 'External' : 'None'
    virtualNetworkConfiguration: enableVNet ? {
      subnetResourceId: privateEndpointSubnetId
    } : null
  }
}

// Named Value for OpenAI Endpoint (if provided)
resource openAINamedValue 'Microsoft.ApiManagement/service/namedValues@2023-09-01-preview' = if (openAIEndpoint != '') {
  parent: apim
  name: 'openai-endpoint'
  properties: {
    displayName: 'openai-endpoint'
    value: openAIEndpoint
    secret: false
  }
}

// Named Value for AI Search Endpoint (if provided)
resource aiSearchNamedValue 'Microsoft.ApiManagement/service/namedValues@2023-09-01-preview' = if (aiSearchEndpoint != '') {
  parent: apim
  name: 'aisearch-endpoint'
  properties: {
    displayName: 'aisearch-endpoint'
    value: aiSearchEndpoint
    secret: false
  }
}

// OpenAI API (if endpoint provided)
resource openAIApi 'Microsoft.ApiManagement/service/apis@2023-09-01-preview' = if (openAIEndpoint != '') {
  parent: apim
  name: 'openai-api'
  properties: {
    displayName: 'Azure OpenAI API'
    description: 'Proxy API for Azure OpenAI Service'
    subscriptionRequired: true
    path: 'openai'
    protocols: [
      'https'
    ]
    serviceUrl: openAIEndpoint
    format: 'openapi-link'
    value: 'https://raw.githubusercontent.com/Azure/azure-rest-api-specs/main/specification/cognitiveservices/data-plane/AzureOpenAI/inference/stable/2024-02-01/inference.json'
  }
}

// AI Search API (if endpoint provided)
resource aiSearchApi 'Microsoft.ApiManagement/service/apis@2023-09-01-preview' = if (aiSearchEndpoint != '') {
  parent: apim
  name: 'aisearch-api'
  properties: {
    displayName: 'Azure AI Search API'
    description: 'Proxy API for Azure AI Search Service'
    subscriptionRequired: true
    path: 'search'
    protocols: [
      'https'
    ]
    serviceUrl: aiSearchEndpoint
  }
}

// Rate Limiting Policy (global)
resource globalPolicy 'Microsoft.ApiManagement/service/policies@2023-09-01-preview' = {
  parent: apim
  name: 'policy'
  properties: {
    value: '''
      <policies>
        <inbound>
          <base />
          <rate-limit calls="100" renewal-period="60" />
          <cors>
            <allowed-origins>
              <origin>*</origin>
            </allowed-origins>
            <allowed-methods>
              <method>GET</method>
              <method>POST</method>
              <method>PUT</method>
              <method>DELETE</method>
              <method>OPTIONS</method>
            </allowed-methods>
            <allowed-headers>
              <header>*</header>
            </allowed-headers>
          </cors>
        </inbound>
        <backend>
          <base />
        </backend>
        <outbound>
          <base />
        </outbound>
        <on-error>
          <base />
        </on-error>
      </policies>
    '''
    format: 'xml'
  }
}

// RBAC: Grant Container Apps MI access to APIM
resource apimReaderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (containerAppsMIObjectId != '') {
  name: guid(apim.id, containerAppsMIObjectId, 'API Management Service Reader')
  scope: apim
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '71522526-b88f-4d52-b57f-d31fc3546d0d') // API Management Service Reader
    principalId: containerAppsMIObjectId
    principalType: 'ServicePrincipal'
  }
}

output apimId string = apim.id
output apimName string = apim.name
output gatewayUrl string = apim.properties.gatewayUrl
output managementApiUrl string = apim.properties.managementApiUrl
output developerPortalUrl string = apim.properties.developerPortalUrl
