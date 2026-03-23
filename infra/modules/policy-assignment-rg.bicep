// Azure Policy assignment module for resource group scope

param policyAssignmentName string = 'require-tags-policy'
param requiredTags array = ['reason', 'purpose']
param enforcementMode string = 'Default' // 'Default' = Deny, 'DoNotEnforce' = Audit only
param policySetDefinitionId string

// Assign the policy initiative to the current resource group
resource policyAssignment 'Microsoft.Authorization/policyAssignments@2022-06-01' = {
  name: policyAssignmentName
  properties: {
    displayName: 'Require Tags on Resources'
    description: 'Ensures all resources have required tags: ${join(requiredTags, ', ')}'
    policyDefinitionId: policySetDefinitionId
    enforcementMode: enforcementMode
    nonComplianceMessages: [for tag in requiredTags: {
      message: 'Resource must have the "${tag}" tag defined.'
      policyDefinitionReferenceId: 'require-${tag}-tag'
    }]
  }
}

// Also add inherit tags from resource group policy
var inheritTagPolicyDefinitionId = '/providers/Microsoft.Authorization/policyDefinitions/ea3f8e5c-26fa-4eb3-b2a3-5b3f4e8e5a1a' // Inherit a tag from resource group if missing

resource inheritTagsAssignment 'Microsoft.Authorization/policyAssignments@2022-06-01' = [for tag in requiredTags: {
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

output policyAssignmentId string = policyAssignment.id
