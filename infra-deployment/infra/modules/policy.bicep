// Azure Policy module - Enforces required tags

param policyAssignmentName string = 'require-tags-policy'
param requiredTags array = ['reason', 'purpose']
param enforcementMode string = 'Default' // 'Default' = Deny, 'DoNotEnforce' = Audit only

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

// Assign the policy initiative to the resource group
resource policyAssignment 'Microsoft.Authorization/policyAssignments@2022-06-01' = {
  name: policyAssignmentName
  properties: {
    displayName: 'Require Tags on Resources'
    description: 'Ensures all resources have required tags: ${join(requiredTags, ', ')}'
    policyDefinitionId: policySetDefinition.id
    enforcementMode: enforcementMode
    nonComplianceMessages: [for (tag, i) in requiredTags: {
      message: 'Resource must have the "${tag}" tag defined.'
      policyDefinitionReferenceId: 'require-${tag}-tag'
    }]
  }
}

// Also add inherit tags from resource group policy
var inheritTagPolicyDefinitionId = '/providers/Microsoft.Authorization/policyDefinitions/ea3f8e5c-26fa-4eb3-b2a3-5b3f4e8e5a1a' // Inherit a tag from resource group if missing

resource inheritTagsAssignment 'Microsoft.Authorization/policyAssignments@2022-06-01' = [for (tag, i) in requiredTags: {
  name: 'inherit-${tag}-tag'
  properties: {
    displayName: 'Inherit ${tag} tag from resource group'
    description: 'Adds the ${tag} tag from the resource group when any resource missing this tag is created or updated.'
    policyDefinitionId: inheritTagPolicyDefinitionId
    enforcementMode: 'Default'
    parameters: {
      tagName: {
        value: tag
      }
    }
  }
}]

output policySetDefinitionId string = policySetDefinition.id
output policyAssignmentId string = policyAssignment.id
output requiredTagsList array = requiredTags
