# Azure AI Landing Zone - Infrastructure Deployment

Enterprise-grade Azure AI infrastructure with automatic region fallback, comprehensive security, and modular architecture.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Quick Start](#quick-start)
- [Configuration Reference](#configuration-reference)
- [Services Reference](#services-reference)
- [Subservice Control](#subservice-control)
- [Security Model](#security-model)
- [Permissions Matrix](#permissions-matrix)
- [Network Architecture](#network-architecture)
- [Deployment](#deployment)
- [Cost Estimation](#cost-estimation)
- [Troubleshooting](#troubleshooting)

---

## Overview

This project deploys a complete Azure AI Landing Zone infrastructure using:

- **Azure Bicep** for Infrastructure as Code
- **Azure Developer CLI (azd)** for streamlined deployment (optional)
- **PowerShell/Bash scripts** for automated configuration
- **TOML configuration** for readable settings, converted to deployment parameters by scripts
- **Automatic region fallback** for resilient deployment

### Key Features

| Feature | Description |
|---------|-------------|
|  **Region Fallback** | Automatically selects first available region from your list |
|  **Zero-Trust Security** | Private endpoints, VNet isolation, RBAC |
|  **AI-Ready** | OpenAI, AI Search, Cosmos DB pre-configured |
|  **Full Observability** | Log Analytics, App Insights, configurable retention |
|  **Modular Design** | Enable only the services you need |
|  **Governance** | Azure Policy for required tags enforcement |
|  **Secrets Management** | Auto-generated passwords stored in Key Vault |

---

## Architecture

### Core Services

| Service | Purpose | Key Features |
|---------|---------|--------------|
| **Azure OpenAI** | LLM inference & embeddings | Content filtering, multiple model deployments |
| **Cosmos DB** | NoSQL & Graph database | Serverless option, geo-replication, analytical storage |
| **Azure SQL** | Relational database | Zone redundancy, password in Key Vault |
| **AI Search** | Semantic & vector search | Configurable replicas, semantic tiers |
| **Container Apps** | Serverless containers | Dapr support, zone redundancy, custom domains |
| **Container Registry** | Docker images | Geo-replication, private endpoint |
| **Data Lake Gen2** | Object storage | Hierarchical namespace, private endpoint |
| **Key Vault** | Secrets management | RBAC, soft delete, SQL password storage |
| **Monitoring** | Observability | Log Analytics, App Insights, configurable retention |

### Optional Services (NEW)

| Service | Purpose | Key Features |
|---------|---------|--------------|
| **API Management** | API gateway | OpenAI proxying, rate limiting, caching |
| **Azure Front Door** | Global CDN | WAF protection, global load balancing |
| **Redis Cache** | Caching layer | Chat history, session state |
| **Azure Policy** | Governance | Required tag enforcement |

### Project Structure

```text
repo-root/
  README.md                   # This file
  .gitignore                  # Git ignore rules
  azd/
    azure.yaml                # Azure Developer CLI configuration
  config/
    config.toml               # Your local deployment configuration (gitignored)
    config.example.toml       # Example configuration template
  scripts/
    deploy.ps1                # PowerShell deployment script
    deploy.sh                 # Bash deployment script
    validate.ps1              # Pre-deployment validation
    generate-diagram.py       # Diagram generator
  infra/
    main.bicep                # Main orchestration template
    main.bicepparam           # Baseline Bicep parameter file for validate/what-if
    modules/
      aisearch.bicep          # Azure AI Search
      apim.bicep              # API Management (NEW)
      containerapps.bicep     # Container Apps + Dapr
      containerregistry.bicep # ACR
      cosmosdb.bicep          # Cosmos DB with SQL roles
      datalake.bicep          # Data Lake Gen2
      frontdoor.bicep         # Azure Front Door (NEW)
      identities.bicep        # Managed Identity
      keyvault.bicep          # Key Vault
      monitoring.bicep        # Log Analytics + App Insights
      networking.bicep        # VNet, subnets, NSGs
      openai.bicep            # Azure OpenAI
      policy.bicep            # Azure Policy (NEW)
      rbac.bicep              # RBAC assignments
      redis.bicep             # Redis Cache (NEW)
      sqldb.bicep             # Azure SQL Database
```

---

## Quick Start

**TL;DR:**
```powershell
# 1. Configure
Copy-Item .\config\config.example.toml .\config\config.toml
# Edit .\config\config.toml with your settings

# 2. Deploy
.\scripts\deploy.ps1
```

**Linux/Mac:**
```bash
cp ./config/config.example.toml ./config/config.toml
./scripts/deploy.sh
```

---

## Configuration Reference

### Core Configuration

```toml
[project]
name = "myaiproject"           # Project name (used in resource naming)
locations = ["eastus", "westus2", "westeurope"]  # Region fallback list
prefixes = ["dev", "uat", "prod"]  # Deploy one stack per prefix (PowerShell script)
environment = "dev"             # Backward-compatible fallback when prefixes/prefix not set

[subscription]
id = ""                        # Optional: specific subscription ID

[admin]
emails = ["admin@company.com"] # Admin user emails (resolved to Object IDs)
```

### Governance (NEW)

```toml
[policy]
requiredTags = ["reason", "purpose"]  # Tags enforced by Azure Policy
enforcementMode = "Default"            # "Default" = Deny, "DoNotEnforce" = Audit

[tags]
Environment = "Development"
ManagedBy = "AzureDeveloperCLI"
Project = "AI-LandingZone"
reason = "AI Landing Zone"      # Required tag
purpose = "Enterprise AI"       # Required tag
```

### Network Configuration

```toml
[networking]
enabled = true
vnetAddressPrefix = "10.0.0.0/16"
containerAppsSubnetPrefix = "10.0.0.0/23"
privateEndpointSubnetPrefix = "10.0.2.0/24"
sqlSubnetPrefix = "10.0.3.0/24"
apimSubnetPrefix = "10.0.4.0/27"
```

`networking.enabled = true` turns on networking features globally; each service can still opt in/out of private endpoints.

Subnets/NSGs are created only when needed by enabled services:
- `snet-containerapps` for `services.containerApps.enabled = true`
- `snet-sql` for `services.sqldb.enabled = true`
- `snet-apim` for `services.apim.enabled = true`
- `snet-privateendpoints` only when at least one enabled service has `privateEndpointEnabled = true`

Example mixed mode:
```toml
[networking]
enabled = true

[services.aisearch]
enabled = true
privateEndpointEnabled = true

[services.datalake]
enabled = true
privateEndpointEnabled = false
```

### Services Configuration

#### Azure OpenAI

```toml
[services.openai]
enabled = true
privateEndpointEnabled = true        # Set false to keep OpenAI public even when networking.enabled=true
contentFilterPolicy = ""               # Optional; leave empty to skip explicit RAI policy
deployments = [
  { name = "gpt-5-mini", model = "gpt-5-mini", version = "2025-08-07", sku = "GlobalStandard", capacity = 150, raiPolicyName = "" },
  { name = "text-embedding-3-small", model = "text-embedding-3-small", version = "1", capacity = 10, raiPolicyName = "" }
]
```

| Option | Description |
|--------|-------------|
| `contentFilterPolicy` | Default content filter for all deployments |
| `deployments[].sku` | Deployment SKU (`GlobalStandard`, `Standard`, etc.) |
| `deployments[].raiPolicyName` | Per-deployment RAI policy override |
| `deployments[].capacity` | TPM capacity (in thousands) |

#### Cosmos DB

```toml
[services.cosmosdb]
enabled = true
privateEndpointEnabled = true
enableNoSQL = true              # Enable SQL API
enableGremlin = true            # Enable Graph API
consistencyLevel = "Session"    # Consistency level
enableServerless = false        # Serverless mode (cost-effective for dev)
enableAnalyticalStorage = false # Analytical storage for HTAP
additionalRegions = []          # e.g., ["westus2", "westeurope"]
```

| Option | Description |
|--------|-------------|
| `enableServerless` | Use serverless capacity mode (no RU provisioning) |
| `enableAnalyticalStorage` | Enable analytical store for Azure Synapse Link |
| `additionalRegions` | Multi-region write support locations |

#### Azure SQL Database

```toml
[services.sqldb]
enabled = true
privateEndpointEnabled = true
databaseSku = "S1"             # SKU tier
zoneRedundant = false          # Zone redundancy (production)
allowedIpRules = [
  { startIpAddress = "203.0.113.10", endIpAddress = "203.0.113.20" }
]
```

The SQL admin password is automatically:
1. Generated with strong random characters
2. Stored in Key Vault as `sql-admin-password`
3. Connection string stored as `sql-connection-string`

#### AI Search

```toml
[services.aisearch]
enabled = true
privateEndpointEnabled = true
sku = "standard"               # basic, standard, standard2, standard3
replicaCount = 1               # 1-12 replicas
partitionCount = 1             # 1, 2, 3, 4, 6, or 12
semanticSearchTier = "free"    # "free", "standard", or "disabled"
```

#### Data Lake Storage

```toml
[services.datalake]
enabled = true
privateEndpointEnabled = true
sku = "Standard_LRS"
isHnsEnabled = true            # Hierarchical namespace (Data Lake Gen2)
containers = ["data", "raw", "curated"]  # Blob containers created by IaC
```

#### Container Apps

```toml
[services.containerApps]
enabled = true
enableDapr = false             # Enable Dapr sidecar
zoneRedundant = false          # Zone redundancy
customDomainName = ""          # Custom domain (e.g., "apps.company.com")
customDomainCertificateId = "" # Certificate resource ID
```

#### Container Registry

```toml
[services.containerRegistry]
enabled = true
privateEndpointEnabled = true
sku = "Premium"                       # Basic, Standard, Premium
geoReplicationLocations = []          # Geo-replication locations
```

#### Key Vault

```toml
[services.keyVault]
enabled = true
privateEndpointEnabled = true
sku = "standard"                      # standard or premium
softDeleteRetentionInDays = 90        # 7-90 days
```

#### Monitoring

```toml
[services.monitoring]
enabled = true
retentionInDays = 30                  # Log retention (30-730)
```

### Optional Services (NEW)

#### API Management

```toml
[services.apim]
enabled = false
sku = "Developer"                     # Developer, Basic, Standard, Premium
capacity = 1                          # Instance count
publisherEmail = "api@company.com"    # Required
publisherName = "Your Company"        # Required
enableOpenAIProxy = true              # Proxy OpenAI calls
enableSearchProxy = true              # Proxy AI Search calls
rateLimitCallsPerMinute = 100         # Rate limiting
enableCaching = false                 # Response caching
cacheDurationSeconds = 300            # Cache TTL
```

#### Azure Front Door

```toml
[services.frontDoor]
enabled = false
enableWaf = true                      # Web Application Firewall
wafMode = "Prevention"                # "Detection" or "Prevention"
```

#### Redis Cache

```toml
[services.redis]
enabled = false
privateEndpointEnabled = true
sku = "Standard"                      # Basic, Standard, Premium
capacity = 1                          # Cache size (0-6)
```

#### Azure Policy

```toml
[policy]
enabled = true
requiredTags = ["reason", "purpose"]  # Tags to enforce
enforcementMode = "Default"           # "Default" (Deny) or "DoNotEnforce" (Audit)
```

---

## Services Reference

### Enabled by Default

| Service | Config Key | Resources Created |
|---------|------------|-------------------|
| OpenAI | `services.openai` | OpenAI account, model deployments, private endpoint |
| Cosmos DB | `services.cosmosdb` | Account, databases, SQL role assignments, private endpoint |
| SQL DB | `services.sqldb` | Server, database, firewall rules, private endpoint |
| AI Search | `services.aisearch` | Search service, private endpoint |
| Container Apps | `services.containerApps` | Environment, managed identity |
| Container Registry | `services.containerRegistry` | Registry, private endpoint |
| Data Lake | `services.dataLake` | Storage account, containers, private endpoint |
| Key Vault | `services.keyVault` | Vault, access policies, private endpoint |
| Monitoring | `services.monitoring` | Log Analytics, App Insights |
| Networking | `networking` | VNet plus only the subnets/NSGs needed by enabled services |

### Optional (Disabled by Default)

| Service | Config Key | When to Enable |
|---------|------------|----------------|
| APIM | `services.apim` | API gateway for rate limiting, caching |
| Front Door | `services.frontDoor` | Global CDN with WAF |
| Redis | `services.redis` | Chat history, session caching |
| Policy | `policy` | Tag enforcement and governance |

---

## Subservice Control

| Service | Control in IaC Today | Subservices/Child Config |
|---------|-----------------------|--------------------------|
| OpenAI | Account + model deployments | `services.openai.deployments[]` controls model, version, SKU, capacity, optional RAI policy |
| Data Lake | Storage account + containers | `services.datalake.containers` controls container creation; HNS is enabled for Gen2 |
| AI Search | Search service | SKU/replicas/partitions/semantic tier configurable; indexes/fields/analyzers are created post-deploy via SDK/REST |
| Cosmos DB | Account-level + APIs + regions | API enablement, consistency, serverless, analytical store, extra regions |
| SQL DB | Server/db/firewall | SKU, zone redundancy, IP rules |
| Container Apps | Environment-level controls | Dapr, zone redundancy, custom domain wiring |

AI Search indexes and field schemas are data-plane artifacts and are not currently modeled in the Bicep templates in this repo.

---

## Security Model

### Identity & Access

| Identity Type | Purpose |
|---------------|---------|
| **User-Assigned Managed Identity** | Service-to-service authentication |
| **Admin Object IDs** | Admin user access to all resources |

### RBAC Roles Assigned

Detailed role assignments are included in the **Permissions Matrix** section below.

**Key improvements:**
- Admin emails automatically resolved to Object IDs
- Cosmos DB uses SQL Role Assignments (not Azure RBAC) for data plane
- SQL password stored in Key Vault automatically

### Network Security

| Feature | Description |
|---------|-------------|
| **VNet Isolation** | All services in private VNet |
| **Private Endpoints** | No public internet exposure |
| **Private DNS Zones** | VNet-linked for name resolution |
| **NSGs** | Network security groups on subnets |

---

## Permissions Matrix

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

Each admin user (specified in `config/config.toml`) receives comprehensive access to all services. Admin emails are automatically resolved to Azure AD Object IDs during deployment.

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
- Unused admin accounts should be removed from `config/config.toml`

---

## Adding/Removing Permissions

### Add a New Admin User
1. Add email to `config/config.toml`:
   ```toml
   [admin]
   emails = ["existing@company.com", "new@company.com"]
   ```
2. Redeploy with `.\scripts\deploy.ps1`
3. New user automatically gets all roles (resolved to Object ID)

### Remove an Admin User
1. Remove email from `config/config.toml`
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


## Network Architecture

### Private DNS Zones

When VNet is enabled, private DNS zones are created only for enabled services that use private endpoints:

| Zone | Services |
|------|----------|
| `privatelink.openai.azure.com` | Azure OpenAI |
| `privatelink.documents.azure.com` | Cosmos DB |
| `privatelink.database.windows.net` | Azure SQL |
| `privatelink.search.windows.net` | AI Search |
| `privatelink.blob.core.windows.net` | Data Lake |
| `privatelink.dfs.core.windows.net` | Data Lake (DFS) |
| `privatelink.vaultcore.azure.net` | Key Vault |
| `privatelink.azurecr.io` | Container Registry |
| `privatelink.redis.cache.windows.net` | Redis Cache |
| `privatelink.azure-api.net` | API Management |

Each created zone is automatically linked to the VNet for proper name resolution.

---

## Deployment

### Prerequisites

- Azure CLI installed and authenticated
- Bicep CLI installed (required for template compilation)
- PowerShell 7+ (Windows) or Bash (Linux/Mac)
- Contributor + User Access Administrator on subscription
- Azure AD permissions to read user objects

Install Bicep with WinGet (Windows):
```powershell
winget install Microsoft.Bicep
```

If `bicep` is not found after install, add the WinGet package path for the current session:
```powershell
$env:PATH = 'C:\Users\emili\AppData\Local\Microsoft\WinGet\Packages\Microsoft.Bicep_Microsoft.Winget.Source_8wekyb3d8bbwe;' + $env:PATH
```

### Deployment Methods

#### Method 1: PowerShell Script (Recommended)

```powershell
.\scripts\deploy.ps1
```

Deploy multiple prefixes/environments in one run (configured in `config/config.toml`):

```toml
[project]
prefixes = ["dev", "uat", "prod"]
resourceGroupName = "rg-myaiproject-{prefix}-{location}"
```

#### Method 2: Bash Script

```bash
./scripts/deploy.sh
```

#### Method 3: What-If Preview (Recommended First)

```powershell
.\scripts\deploy.ps1 -WhatIf
```

```bash
./scripts/deploy.sh config/config.toml --what-if
```

`scripts/deploy.sh` accepts positional arguments: `<config-file> [--what-if]`.

This runs Azure CLI what-if preview to validate and show planned resource changes without creating resources.

#### Method 4: Azure Developer CLI (infra-first)

```bash
cd azd
azd provision
```

Use `azd up` only when you add application services to `azd/azure.yaml` and want the full provision + package + deploy workflow.

### Generate Architecture Diagram

Generate a diagram directly from `config/config.toml`:

```powershell
python .\scripts\generate-diagram.py --config .\config\config.toml --out-dir .\diagrams --name architecture
```

Outputs:
- `diagrams/architecture.mmd` (Mermaid diagram)
- `diagrams/architecture-summary.md` (service/network summary)

This supports mixed networking modes (for example, AI Search private endpoint on while Data Lake remains public).

### What Happens During Deployment

1. **Configuration Loading**: Reads `config/config.toml`
2. **Email Resolution**: Converts admin emails to Object IDs
3. **Region Testing**: Checks service availability per region
4. **Region Selection**: Picks first available region
5. **Resource Group Creation**: Creates or uses existing RG
6. **Bicep Deployment**: Deploys all enabled modules
7. **Output Display**: Shows endpoints and connection info

### Validation

Before deploying, validate your configuration:

```powershell
.\scripts\validate.ps1
```

This checks:
- Configuration syntax
- Required fields
- Azure login status
- Permission levels

---

## Cost Estimation

### Development Environment (Minimal)

| Service | Configuration | Est. Monthly Cost |
|---------|---------------|-------------------|
| OpenAI | GPT-5 mini @ 10K TPM | $50-200 |
| Cosmos DB | Serverless | $0-50 |
| SQL DB | S1 | ~$30 |
| AI Search | Basic | ~$70 |
| Container Apps | Consumption | $0-20 |
| ACR | Standard | ~$20 |
| Key Vault | Standard | ~$3 |
| Monitoring | 30 days | ~$10 |
| **Total** | | **~$200-400/month** |

### Production Environment (Recommended)

| Service | Configuration | Est. Monthly Cost |
|---------|---------------|-------------------|
| OpenAI | GPT-5 mini @ 50K TPM | $200-1000 |
| Cosmos DB | Provisioned + Geo | $200-500 |
| SQL DB | S3 + Zone Redundant | ~$150 |
| AI Search | Standard S2 | ~$250 |
| Container Apps | Zone Redundant | $50-200 |
| ACR | Premium + Geo | ~$50 |
| Key Vault | Premium | ~$10 |
| Monitoring | 90 days | ~$50 |
| APIM | Standard | ~$350 |
| Front Door | Standard + WAF | ~$100 |
| Redis | Standard | ~$50 |
| **Total** | | **~$1500-2500/month** |

*Costs vary based on usage. Use [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/) for accurate estimates.*

---

## Troubleshooting

### Common Issues

#### "No regions support all required services"

```
Solution: 
1. Add more regions to `config/config.toml` locations array
2. Disable services you don't need
3. Check Azure region availability: https://azure.microsoft.com/global-infrastructure/services/
```

#### "User not found in Azure AD"

```
Solution:
- Verify the email is a valid Azure AD UPN
- Ensure you have permission to read user objects
- For guest users, use their full email including #EXT#
```

#### "Insufficient permissions"

```
Solution:
- Ensure you have Contributor role on subscription
- Ensure you have User Access Administrator for RBAC
- For Cosmos DB data plane, SQL Role Assignments are created automatically
```

#### "Private endpoint DNS not resolving"

```
Solution:
1. Verify VNet is enabled in config
2. Check DNS zone VNet links exist in Azure portal
3. Restart client to refresh DNS cache
4. If using Azure VM, ensure it's in the same VNet
```

#### "SQL password not in Key Vault"

```
Solution:
- Password is stored as 'sql-admin-password' secret
- Ensure Key Vault is enabled in config
- Verify deployment completed successfully
```

### Logs and Diagnostics

```bash
# Check deployment status
az deployment group show --name main --resource-group <RG_NAME>

# View deployment operations
az deployment group operation list --name main --resource-group <RG_NAME>

# Query Log Analytics
az monitor log-analytics query \
  --workspace <WORKSPACE_ID> \
  --analytics-query "AzureDiagnostics | take 10"
```

---

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with `.\scripts\validate.ps1`
5. Deploy to a test environment
6. Submit a pull request

### Development Guidelines

- Follow Bicep best practices
- Add new services as separate modules
- Update `config/config.example.toml` with new options
- Document new parameters in this README
- Update the Permissions Matrix section in README for RBAC changes

---

## License

MIT License - see LICENSE file for details.

---

## Support

- **Issues**: Open a GitHub issue
- **Documentation**: See linked markdown files
- **Azure Docs**: [Azure AI Services](https://learn.microsoft.com/azure/ai-services/)

---

## Acknowledgments

Built with:
- [Azure Bicep](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)
- [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/)
- [Azure AI Services](https://azure.microsoft.com/products/ai-services/)

---

**Ready to deploy?** Start at the [Quick Start](#quick-start) section above for a 5-minute setup.

