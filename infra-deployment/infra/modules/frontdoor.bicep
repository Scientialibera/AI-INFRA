// Azure Front Door module with WAF

param frontDoorName string
param wafPolicyName string = ''
param enableWaf bool = false
param customDomains array = []
param containerAppsDefaultDomain string = ''
param apimGatewayHostname string = ''
param tags object = {}

// Front Door Profile
resource frontDoor 'Microsoft.Cdn/profiles@2024-02-01' = {
  name: frontDoorName
  location: 'global'
  tags: tags
  sku: {
    name: enableWaf ? 'Premium_AzureFrontDoor' : 'Standard_AzureFrontDoor'
  }
}

// WAF Policy (if enabled)
resource wafPolicy 'Microsoft.Network/FrontDoorWebApplicationFirewallPolicies@2024-02-01' = if (enableWaf && wafPolicyName != '') {
  name: wafPolicyName
  location: 'global'
  tags: tags
  sku: {
    name: 'Premium_AzureFrontDoor'
  }
  properties: {
    policySettings: {
      enabledState: 'Enabled'
      mode: 'Prevention'
      requestBodyCheck: 'Enabled'
    }
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'Microsoft_DefaultRuleSet'
          ruleSetVersion: '2.1'
          ruleSetAction: 'Block'
        }
        {
          ruleSetType: 'Microsoft_BotManagerRuleSet'
          ruleSetVersion: '1.0'
          ruleSetAction: 'Block'
        }
      ]
    }
  }
}

// Front Door Endpoint
resource frontDoorEndpoint 'Microsoft.Cdn/profiles/afdEndpoints@2024-02-01' = {
  parent: frontDoor
  name: '${frontDoorName}-endpoint'
  location: 'global'
  properties: {
    enabledState: 'Enabled'
  }
}

// Origin Group for Container Apps
resource containerAppsOriginGroup 'Microsoft.Cdn/profiles/originGroups@2024-02-01' = if (containerAppsDefaultDomain != '') {
  parent: frontDoor
  name: 'container-apps-origin-group'
  properties: {
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
      additionalLatencyInMilliseconds: 50
    }
    healthProbeSettings: {
      probePath: '/health'
      probeRequestType: 'HEAD'
      probeProtocol: 'Https'
      probeIntervalInSeconds: 100
    }
    sessionAffinityState: 'Disabled'
  }
}

// Origin for Container Apps
resource containerAppsOrigin 'Microsoft.Cdn/profiles/originGroups/origins@2024-02-01' = if (containerAppsDefaultDomain != '') {
  parent: containerAppsOriginGroup
  name: 'container-apps-origin'
  properties: {
    hostName: containerAppsDefaultDomain
    httpPort: 80
    httpsPort: 443
    originHostHeader: containerAppsDefaultDomain
    priority: 1
    weight: 1000
    enabledState: 'Enabled'
  }
}

// Origin Group for APIM
resource apimOriginGroup 'Microsoft.Cdn/profiles/originGroups@2024-02-01' = if (apimGatewayHostname != '') {
  parent: frontDoor
  name: 'apim-origin-group'
  properties: {
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
      additionalLatencyInMilliseconds: 50
    }
    healthProbeSettings: {
      probePath: '/status-0123456789abcdef'
      probeRequestType: 'HEAD'
      probeProtocol: 'Https'
      probeIntervalInSeconds: 100
    }
    sessionAffinityState: 'Disabled'
  }
}

// Origin for APIM
resource apimOrigin 'Microsoft.Cdn/profiles/originGroups/origins@2024-02-01' = if (apimGatewayHostname != '') {
  parent: apimOriginGroup
  name: 'apim-origin'
  properties: {
    hostName: apimGatewayHostname
    httpPort: 80
    httpsPort: 443
    originHostHeader: apimGatewayHostname
    priority: 1
    weight: 1000
    enabledState: 'Enabled'
  }
}

// Route for Container Apps
resource containerAppsRoute 'Microsoft.Cdn/profiles/afdEndpoints/routes@2024-02-01' = if (containerAppsDefaultDomain != '') {
  parent: frontDoorEndpoint
  name: 'container-apps-route'
  properties: {
    originGroup: {
      id: containerAppsOriginGroup.id
    }
    supportedProtocols: [
      'Http'
      'Https'
    ]
    patternsToMatch: [
      '/app/*'
    ]
    forwardingProtocol: 'HttpsOnly'
    linkToDefaultDomain: 'Enabled'
    httpsRedirect: 'Enabled'
  }
  dependsOn: [
    containerAppsOrigin
  ]
}

// Route for APIM
resource apimRoute 'Microsoft.Cdn/profiles/afdEndpoints/routes@2024-02-01' = if (apimGatewayHostname != '') {
  parent: frontDoorEndpoint
  name: 'apim-route'
  properties: {
    originGroup: {
      id: apimOriginGroup.id
    }
    supportedProtocols: [
      'Http'
      'Https'
    ]
    patternsToMatch: [
      '/api/*'
    ]
    forwardingProtocol: 'HttpsOnly'
    linkToDefaultDomain: 'Enabled'
    httpsRedirect: 'Enabled'
  }
  dependsOn: [
    apimOrigin
  ]
}

// Security Policy (WAF association)
resource securityPolicy 'Microsoft.Cdn/profiles/securityPolicies@2024-02-01' = if (enableWaf && wafPolicyName != '') {
  parent: frontDoor
  name: 'waf-security-policy'
  properties: {
    parameters: {
      type: 'WebApplicationFirewall'
      wafPolicy: {
        id: wafPolicy.id
      }
      associations: [
        {
          domains: [
            {
              id: frontDoorEndpoint.id
            }
          ]
          patternsToMatch: [
            '/*'
          ]
        }
      ]
    }
  }
}

output frontDoorId string = frontDoor.id
output frontDoorName string = frontDoor.name
output endpointHostName string = frontDoorEndpoint.properties.hostName
output frontDoorFqdn string = '${frontDoorEndpoint.name}.azurefd.net'
