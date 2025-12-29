# RBAC Permissions Matrix - Azure AI Landing Zone

## Overview

This document details all RBAC (Role-Based Access Control) permissions configured in the deployment, covering both **Service Plane** (control/management) and **Data Plane** (data access) permissions.

**Important**: Admin user emails are resolved to Azure AD Object IDs by the deployment script before being passed to Bicep templates. This ensures proper role assignments.

---

## Container Apps Managed Identity Permissions

The user-assigned managed identity for Container Apps needs access to all services for runtime operations.

### Core Services

| Service | Role | Role ID | Type | Purpose |
|---------|------|---------|------|---------|
| **OpenAI** | Cognitive Services OpenAI User | `5e0bd9bd-7b93-4f28-af87-19fc36ad61bd` | Data Plane | Call OpenAI APIs, use models |
| **Cosmos DB** | Cosmos DB Built-in Data Contributor | `00000000-0000-0000-0000-000000000002` | Data Plane | Read/write documents and graphs |
| **Data Lake** | Storage Blob Data Contributor | `ba92f5b4-2d11-453d-a403-e96b0029c9fe` | Data Plane | Read/write/delete blobs |
| **SQL Database** | SQL DB Contributor | `9b7fa17d-e63e-47b0-bb0a-15c516ac86ec` | Service Plane | Manage databases (not data) |
| **SQL Database** | (AAD Admin) | N/A | Data Plane | Query and modify data via AAD auth |
| **AI Search** | Search Service Contributor | `7ca78c08-252a-4471-8644-bb5ff32d4ba0` | Service Plane | Manage search service |
| **AI Search** | Search Index Data Contributor | `8ebe5a00-799e-43f5-93ac-243d3dce84a7` | Data Plane | Read/write index data |
| **Key Vault** | Key Vault Secrets User | `4633458b-17de-408a-b874-0445c86b69e6` | Data Plane | Read secrets |
| **Container Registry** | AcrPull | `7f951dda-4ed3-4680-a7ca-43fe172d538d` | Data Plane | Pull container images |

### Optional Services (when enabled)

| Service | Role | Role ID | Type | Purpose |
|---------|------|---------|------|---------|
| **API Management** | API Management Service Reader | `71522526-b88f-4d52-b57f-d31fc3546d0d` | Service Plane | Read APIM configuration |
| **Redis Cache** | Redis Cache Contributor | `e0f68234-74aa-48ed-b826-c38b57376e17` | Service Plane | Access Redis cache |

---

## Admin User Permissions

Each admin user (specified in `config.toml`) receives comprehensive access to all services. Admin emails are automatically resolved to Azure AD Object IDs during deployment.

### Resource Group Level

| Role | Role ID | Type | Purpose |
|------|---------|------|---------|
| Contributor | `b24988ac-6180-42a0-ab88-20f7382dd24c` | Service Plane | Full management of all resources |

### Service-Specific Permissions

#### OpenAI

| Role | Role ID | Type | Purpose |
|------|---------|------|---------|
| Cognitive Services OpenAI Contributor | `a001fd3d-188f-4b5d-821b-7da978bf7442` | Service + Data | Deploy models, call APIs, manage service |

#### Cosmos DB

| Role | Role ID | Type | Purpose |
|------|---------|------|---------|
| DocumentDB Account Contributor | `5bd9cd88-fe45-4216-938b-f97437e15450` | Service Plane | Manage Cosmos DB account settings |
| Cosmos DB Built-in Data Contributor | `00000000-0000-0000-0000-000000000002` | Data Plane | Read/write all data in databases |

**Note**: Cosmos DB uses its own SQL Role Assignment system for data plane RBAC, separate from Azure RBAC.

#### Data Lake (Storage)

| Role | Role ID | Type | Purpose |
|------|---------|------|---------|
| Storage Blob Data Owner | `b7e6dc6d-f1e8-4753-8033-0f276bb0955b` | Data Plane | Full access to blobs, manage ACLs |

#### SQL Database

| Role | Role ID | Type | Purpose |
|------|---------|------|---------|
| SQL DB Contributor | `9b7fa17d-e63e-47b0-bb0a-15c516ac86ec` | Service Plane | Manage SQL databases and servers |
| SQL Security Manager | `056cd41c-7e88-42e1-933e-88ba6a50c9c3` | Service Plane | Manage security policies, firewall rules |

**Note**: SQL admin password is automatically generated and stored in Key Vault as `sql-admin-password`.

#### AI Search

| Role | Role ID | Type | Purpose |
|------|---------|------|---------|
| Search Service Contributor | `7ca78c08-252a-4471-8644-bb5ff32d4ba0` | Service Plane | Manage search service configuration |
| Search Index Data Contributor | `8ebe5a00-799e-43f5-93ac-243d3dce84a7` | Data Plane | Create/modify/delete indexes and data |

#### Container Registry

| Role | Role ID | Type | Purpose |
|------|---------|------|---------|
| AcrPush | `8311e382-0749-4cb8-b61a-304f252e45ec` | Data Plane | Push and pull container images |

#### Key Vault

| Role | Role ID | Type | Purpose |
|------|---------|------|---------|
| Key Vault Administrator | `00482a5a-887f-4fb3-b233-3c3c4e4e8e12` | Service + Data | Full management of vault and all secrets/keys/certs |

---

## Permission Summary by Persona

### Application (Container Apps Managed Identity)

 **Can**:
- Call OpenAI models
- Read/write Cosmos DB data
- Read/write Data Lake files
- Query SQL database
- Search and index in AI Search
- Read secrets from Key Vault
- Pull container images
- Access Redis cache (if enabled)

 **Cannot**:
- Deploy new OpenAI models
- Create new databases
- Modify firewall rules
- Delete services
- Manage RBAC

### Admin Users

 **Can**:
- Everything the application can do
- Deploy and configure services
- Create/delete databases
- Manage firewall rules
- View and modify all data
- Grant permissions to other users
- Delete services

 **Cannot**:
- Delete the resource group (needs Owner role)
- Modify subscription-level policies

---

## Secrets Stored in Key Vault

The deployment automatically stores sensitive information in Key Vault:

| Secret Name | Description | Auto-Generated |
|-------------|-------------|----------------|
| `sql-admin-password` | SQL Server admin password |  Yes |
| `sql-connection-string` | Full SQL connection string |  Yes |

---

## Security Considerations

### Principle of Least Privilege
- **Managed Identity**: Only data plane access, no management capabilities
- **Admin Users**: Full access but scoped to resource group
- **No Storage Account Keys**: All access via RBAC and managed identities
- **No SQL Passwords in App**: Application uses AAD authentication

### Private DNS Zone VNet Links
When VNet is enabled, all private DNS zones are linked to the VNet for proper name resolution:
- `privatelink.openai.azure.com`
- `privatelink.documents.azure.com`
- `privatelink.blob.core.windows.net`
- `privatelink.dfs.core.windows.net`
- `privatelink.vaultcore.azure.net`
- `privatelink.database.windows.net`
- `privatelink.search.windows.net`
- `privatelink.azurecr.io`
- `privatelink.redis.cache.windows.net` (if Redis enabled)

### Audit and Compliance
- All RBAC changes logged to Activity Log
- Access patterns visible in Log Analytics
- Regular review of assigned roles recommended
- Unused admin accounts should be removed from config.toml

---

## Adding/Removing Permissions

### Add a New Admin User
1. Add email to `config.toml`:
   ```toml
   [admin]
   emails = ["existing@company.com", "new@company.com"]
   ```
2. Redeploy with `.\deploy.ps1`
3. New user automatically gets all roles (resolved to Object ID)

### Remove an Admin User
1. Remove email from `config.toml`
2. Redeploy - role assignments will be removed

### Grant Custom Permissions
For non-admin users needing specific access:

```bash
# Grant a user read-only access to OpenAI
az role assignment create \
  --assignee user@company.com \
  --role "Cognitive Services OpenAI User" \
  --scope /subscriptions/SUB_ID/resourceGroups/RG_NAME/providers/Microsoft.CognitiveServices/accounts/OPENAI_NAME

# Grant a service principal access to Data Lake
az role assignment create \
  --assignee <SP_OBJECT_ID> \
  --role "Storage Blob Data Reader" \
  --scope /subscriptions/SUB_ID/resourceGroups/RG_NAME/providers/Microsoft.Storage/storageAccounts/STORAGE_NAME
```

---

## Common Permission Issues

### Issue: "Insufficient permissions to complete operation"
**Cause**: Role propagation delay (5-10 minutes)
**Solution**: Wait a few minutes and retry

### Issue: Admin user can't access data
**Cause**: Missing data plane role
**Solution**: Verify user has both service plane AND data plane roles

### Issue: Managed identity access denied
**Cause**: RBAC not propagated or wrong role assigned
**Solution**: Check role assignments in Azure Portal → IAM

### Issue: SQL connection fails with AAD
**Cause**: Managed identity not set as AAD admin
**Solution**: Verify SQL Server AAD authentication configured in sqldb.bicep

### Issue: Private endpoint name resolution fails
**Cause**: Private DNS zone not linked to VNet
**Solution**: Verify VNet links exist on all private DNS zones

---

## Verification Commands

Check managed identity roles:
```bash
# Get managed identity object ID
MI_ID=$(az identity show --name <MI_NAME> --resource-group <RG_NAME> --query principalId -o tsv)

# List all role assignments
az role assignment list --assignee $MI_ID --output table
```

Check admin user roles:
```bash
# Get user object ID
USER_ID=$(az ad user show --id user@company.com --query id -o tsv)

# List all role assignments
az role assignment list --assignee $USER_ID --scope /subscriptions/<SUB_ID>/resourceGroups/<RG_NAME> --output table
```

Check Cosmos DB SQL Role Assignments:
```bash
# List Cosmos DB role assignments
az cosmosdb sql role assignment list \
  --account-name <COSMOS_NAME> \
  --resource-group <RG_NAME> \
  --output table
```

---

## Role Definitions Reference

All Azure built-in roles: https://learn.microsoft.com/azure/role-based-access-control/built-in-roles

Key roles used in this deployment:
- [Cognitive Services Roles](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/ai-machine-learning)
- [Cosmos DB Roles](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/databases)
- [Storage Roles](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/storage)
- [SQL Roles](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/databases)
- [Search Roles](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/analytics)

---

## Summary

 **Managed Identity**: Data plane access only (application runtime)
 **Admin Users**: Both service plane + data plane (full access)
 **Object ID Resolution**: Admin emails automatically resolved to Azure AD Object IDs
 **No Hard-Coded Credentials**: All access via Azure AD
 **Secrets in Key Vault**: SQL password and connection string stored securely
 **Auditable**: All access logged and traceable
 **Granular**: Different roles for different services
 **Secure**: Least-privilege by default
 **VNet Linked DNS**: Private endpoints resolve correctly within VNet

This permissions matrix ensures your AI infrastructure is secure, compliant, and follows Azure best practices.
