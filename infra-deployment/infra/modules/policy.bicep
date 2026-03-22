// Azure Policy module - Enforces required tags
targetScope = 'subscription'

param requiredTags array = ['reason', 'purpose']

// Built-in policy definition for requiring tags
var requireTagPolicyDefinitionId = '/providers/Microsoft.Authorization/policyDefinitions/871b6d14-10aa-478d-b590-94f262ecfa99' // Require a tag on resources

// Create a policy initiative (policy set) that combines all required tags
resource policySetDefinition 'Microsoft.Authorization/policySetDefinitions@2021-06-01' = {
  name: 'require-tags-initiative'
  properties: {
    displayName: 'Require Tags Initiative'
    description: 'This initiative requires specific tags on all resources'
    policyType: 'Custom'
    metadata: {
      category: 'Tags'
    }
    parameters: {}
    policyDefinitions: [for (tag, i) in requiredTags: {
      policyDefinitionId: requireTagPolicyDefinitionId
      policyDefinitionReferenceId: 'require-${tag}-tag'
      parameters: {
        tagName: {
          value: tag
        }
      }
    }]
  }
}

output policySetDefinitionId string = policySetDefinition.id
output requiredTagsList array = requiredTags
