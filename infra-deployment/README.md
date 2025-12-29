# Azure AI Landing Zone - Infrastructure Deployment

Enterprise-grade Azure AI infrastructure with automatic region fallback, comprehensive security, and modular architecture.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Quick Start](#quick-start)
- [Configuration Reference](#configuration-reference)
- [Services Reference](#services-reference)
- [Security Model](#security-model)
- [Network Architecture](#network-architecture)
- [Deployment](#deployment)
- [Cost Estimation](#cost-estimation)
- [Troubleshooting](#troubleshooting)
- [Future Roadmap](#future-roadmap)

---

## Overview

This project deploys a complete Azure AI Landing Zone infrastructure using:

- **Azure Bicep** for Infrastructure as Code
- **Azure Developer CLI (azd)** for streamlined deployment (optional)
- **PowerShell/Bash scripts** for automated configuration
- **TOML configuration** for simple, readable settings
- **Automatic region fallback** for resilient deployment

### Key Features

| Feature | Description |
|---------|-------------|
| 🌍 **Region Fallback** | Automatically selects first available region from your list |
| 🔐 **Zero-Trust Security** | Private endpoints, VNet isolation, RBAC |
| 🤖 **AI-Ready** | OpenAI, AI Search, Cosmos DB pre-configured |
| 📊 **Full Observability** | Log Analytics, App Insights, configurable retention |
| 🏗️ **Modular Design** | Enable only the services you need |
| 🏷️ **Governance** | Azure Policy for required tags enforcement |
| 🔑 **Secrets Management** | Auto-generated passwords stored in Key Vault |

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

```
infra-deployment/
├── azure.yaml                 # Azure Developer CLI configuration
├── config.toml                # Your deployment configuration
├── config.example.toml        # Example configuration template
├── deploy.ps1                 # PowerShell deployment script
├── deploy.sh                  # Bash deployment script
├── validate.ps1               # Pre-deployment validation
├── QUICKSTART.md              # 5-minute deployment guide
├── README.md                  # This file
├── PERMISSIONS_MATRIX.md      # Detailed permission reference
├── FUTURE_IMPROVEMENTS.md     # Roadmap for enhancements
└── infra/
    ├── main.bicep             # Main orchestration template
    ├── main.parameters.json   # Default parameters
    └── modules/
        ├── aisearch.bicep     # Azure AI Search
        ├── apim.bicep         # API Management (NEW)
        ├── containerapps.bicep # Container Apps + Dapr
        ├── containerregistry.bicep # ACR
        ├── cosmosdb.bicep     # Cosmos DB with SQL roles
        ├── datalake.bicep     # Data Lake Gen2
        ├── frontdoor.bicep    # Azure Front Door (NEW)
        ├── identities.bicep   # Managed Identity
        ├── keyvault.bicep     # Key Vault
        ├── monitoring.bicep   # Log Analytics + App Insights
        ├── networking.bicep   # VNet, subnets, NSGs
        ├── openai.bicep       # Azure OpenAI
        ├── policy.bicep       # Azure Policy (NEW)
        ├── rbac.bicep         # RBAC assignments
        ├── redis.bicep        # Redis Cache (NEW)
        └── sqldb.bicep        # Azure SQL Database
```

---

## Quick Start

For a rapid deployment, see [QUICKSTART.md](QUICKSTART.md).

**TL;DR:**
```powershell
# 1. Configure
Copy-Item config.example.toml config.toml
# Edit config.toml with your settings

# 2. Deploy
.\deploy.ps1
```

---

## Configuration Reference

### Core Configuration

```toml
[project]
name = "myaiproject"           # Project name (used in resource naming)
locations = ["eastus", "westus2", "westeurope"]  # Region fallback list
environment = "dev"             # dev, staging, prod

[subscription]
id = ""                        # Optional: specific subscription ID

[admin]
emails = ["admin@company.com"] # Admin user emails (resolved to Object IDs)
```

### Governance (NEW)

```toml
[governance]
requiredTags = ["reason", "purpose"]  # Tags enforced by Azure Policy
policyEnforcementMode = "Default"     # "Default" = Deny, "DoNotEnforce" = Audit

[tags]
Environment = "Development"
ManagedBy = "AzureDeveloperCLI"
Project = "AI-LandingZone"
reason = "AI Landing Zone"      # Required tag
purpose = "Enterprise AI"       # Required tag
```

### Network Configuration

```toml
[network]
enabled = true                 # Enable VNet isolation
addressPrefixes = ["10.0.0.0/16"]
subnets = [
    { name = "default", prefix = "10.0.0.0/24" },
    { name = "services", prefix = "10.0.1.0/24" },
    { name = "data", prefix = "10.0.2.0/24" },
    { name = "containerApps", prefix = "10.0.3.0/24" },
    { name = "integration", prefix = "10.0.4.0/24" },
    { name = "apim", prefix = "10.0.5.0/24" },           # For APIM
    { name = "privateEndpoints", prefix = "10.0.6.0/24" }
]
```

### Services Configuration

#### Azure OpenAI

```toml
[services.openai]
enabled = true
contentFilterPolicy = "default"        # Content filter policy name
deployments = [
    { name = "gpt-4", model = "gpt-4", version = "2024-05-13", capacity = 10, raiPolicyName = "" },
    { name = "gpt-35-turbo", model = "gpt-35-turbo", version = "0613", capacity = 10, raiPolicyName = "" },
    { name = "text-embedding-ada-002", model = "text-embedding-ada-002", version = "2", capacity = 10, raiPolicyName = "" }
]
```

| Option | Description |
|--------|-------------|
| `contentFilterPolicy` | Default content filter for all deployments |
| `deployments[].raiPolicyName` | Per-deployment RAI policy override |
| `deployments[].capacity` | TPM capacity (in thousands) |

#### Cosmos DB

```toml
[services.cosmosdb]
enabled = true
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
databaseSku = "S1"             # SKU tier
zoneRedundant = false          # Zone redundancy (production)
```

The SQL admin password is automatically:
1. Generated with strong random characters
2. Stored in Key Vault as `sql-admin-password`
3. Connection string stored as `sql-connection-string`

#### AI Search

```toml
[services.aisearch]
enabled = true
sku = "standard"               # basic, standard, standard2, standard3
replicaCount = 1               # 1-12 replicas
partitionCount = 1             # 1, 2, 3, 4, 6, or 12
semanticSearchTier = "free"    # "free", "standard", or "disabled"
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
sku = "Premium"                       # Basic, Standard, Premium
geoReplicationLocations = []          # Geo-replication locations
```

#### Key Vault

```toml
[services.keyVault]
enabled = true
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
| Networking | `network` | VNet, subnets, NSGs, private DNS zones |

### Optional (Disabled by Default)

| Service | Config Key | When to Enable |
|---------|------------|----------------|
| APIM | `services.apim` | API gateway for rate limiting, caching |
| Front Door | `services.frontDoor` | Global CDN with WAF |
| Redis | `services.redis` | Chat history, session caching |
| Policy | `policy` | Tag enforcement and governance |

---

## Security Model

### Identity & Access

| Identity Type | Purpose |
|---------------|---------|
| **User-Assigned Managed Identity** | Service-to-service authentication |
| **Admin Object IDs** | Admin user access to all resources |

### RBAC Roles Assigned

See [PERMISSIONS_MATRIX.md](PERMISSIONS_MATRIX.md) for detailed role assignments.

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

## Network Architecture

### Private DNS Zones

When VNet is enabled, these private DNS zones are created with VNet links:

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

All zones are automatically linked to the VNet for proper name resolution.

---

## Deployment

### Prerequisites

- Azure CLI installed and authenticated
- PowerShell 7+ (Windows) or Bash (Linux/Mac)
- Contributor + User Access Administrator on subscription
- Azure AD permissions to read user objects

### Deployment Methods

#### Method 1: PowerShell Script (Recommended)

```powershell
.\deploy.ps1
```

#### Method 2: Bash Script

```bash
./deploy.sh
```

#### Method 3: Azure Developer CLI

```bash
azd up
```

### What Happens During Deployment

1. **Configuration Loading**: Reads `config.toml`
2. **Email Resolution**: Converts admin emails to Object IDs
3. **Region Testing**: Checks service availability per region
4. **Region Selection**: Picks first available region
5. **Resource Group Creation**: Creates or uses existing RG
6. **Bicep Deployment**: Deploys all enabled modules
7. **Output Display**: Shows endpoints and connection info

### Validation

Before deploying, validate your configuration:

```powershell
.\validate.ps1
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
| OpenAI | GPT-4 @ 10K TPM | $50-200 |
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
| OpenAI | GPT-4 @ 50K TPM | $200-1000 |
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
1. Add more regions to config.toml locations array
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

## Future Roadmap

See [FUTURE_IMPROVEMENTS.md](FUTURE_IMPROVEMENTS.md) for planned enhancements including:

- GitHub Actions / Azure Pipelines CI/CD
- Disaster Recovery configuration
- Azure Firewall integration
- Azure Bastion for secure access
- Backup and restore automation
- Multi-environment (dev/staging/prod) templates
- Terraform port of Bicep templates
- Cost management and budgets

---

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with `.\validate.ps1`
5. Deploy to a test environment
6. Submit a pull request

### Development Guidelines

- Follow Bicep best practices
- Add new services as separate modules
- Update config.example.toml with new options
- Document new parameters in this README
- Update PERMISSIONS_MATRIX.md for RBAC changes

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

**Ready to deploy?** Start with [QUICKSTART.md](QUICKSTART.md) for a 5-minute setup! 🚀
