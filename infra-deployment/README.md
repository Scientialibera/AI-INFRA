# Azure AI Landing Zone - Enterprise Infrastructure Deployment

This repository contains **enterprise-grade** Azure infrastructure deployment code for AI projects using **Azure Developer CLI (azd)** and **Bicep**.

## Overview

This deployment creates a secure, scalable, and production-ready landing zone for AI workloads with the following features:

- **Modular Service Deployment**: Enable/disable services as needed
- **Secure Networking**: VNet with private endpoints, NSGs, and private DNS zones
- **Identity & Access Management**: Managed identities and comprehensive RBAC
- **Deterministic Naming**: All resource names generated from project configuration
- **Idempotent Deployments**: Safe to run multiple times
- **Multi-Admin Support**: Automatically grant permissions to specified admin users

## Architecture

### Azure Services Deployed

| Service | Purpose | Optional |
|---------|---------|----------|
| **Azure OpenAI** | LLM and embedding models |  |
| **Cosmos DB** | NoSQL document & graph database |  |
| **Azure Data Lake Gen2** | Large-scale data storage |  |
| **Azure SQL Database** | Relational database |  |
| **Azure AI Search** | Cognitive search & vector search |  |
| **Container Apps** | Serverless container hosting |  |
| **Container Registry** | Container image storage |  |
| **Key Vault** | Secrets & certificate management |  |
| **Log Analytics** | Centralized logging |  |
| **Application Insights** | Application monitoring |  |

### Network Architecture

When VNet is enabled:
- **Virtual Network** with dedicated subnets
  - Container Apps subnet
  - Private Endpoints subnet
  - SQL subnet
- **Private Endpoints** for all services
- **Network Security Groups** for subnet-level security
- **Private DNS Zones** for private endpoint name resolution

### Security & Identity

- **Managed Identity**: User-assigned identity for Container Apps with access to all services
- **RBAC Roles**: Least-privilege access for service-to-service communication
- **Admin Access**: Automated RBAC assignments for admin users across all services
- **Network Isolation**: Optional private networking for all services

## Prerequisites

1. **Azure CLI** (version 2.50.0 or later)
   ```bash
   az --version
   ```
   Install from: https://aka.ms/azure-cli

2. **Azure Developer CLI (azd)** - OPTIONAL but recommended
   ```bash
   azd version
   ```
   Install from: https://aka.ms/azd

3. **Azure Subscription** with Owner or Contributor role

4. **For Bash deployment**: Python 3.7+ with `tomli` package

## Quick Start

### Option 1: Using Azure Developer CLI (azd) - Recommended

```bash
# 1. Navigate to the deployment folder
cd infra-deployment

# 2. Edit config.toml with your settings
# See Configuration section below

# 3. Initialize azd (first time only)
azd init

# 4. Deploy
azd up
```

### Option 2: Using PowerShell Script

```powershell
# 1. Navigate to the deployment folder
cd infra-deployment

# 2. Edit config.toml with your settings

# 3. Run deployment
.\deploy.ps1

# Optional: Run in what-if mode to preview changes
.\deploy.ps1 -WhatIf
```

### Option 3: Using Bash Script

```bash
# 1. Navigate to the deployment folder
cd infra-deployment

# 2. Make script executable
chmod +x deploy.sh

# 3. Edit config.toml with your settings

# 4. Run deployment
./deploy.sh

# Optional: Run in what-if mode
./deploy.sh config.toml --what-if
```

### Option 4: Direct Azure CLI Deployment

```bash
# 1. Create resource group
az group create --name rg-myai-dev-eastus --location eastus

# 2. Deploy Bicep template
az deployment group create \
  --name ai-landing-zone \
  --resource-group rg-myai-dev-eastus \
  --template-file infra/main.bicep \
  --parameters projectName=myai environment=dev adminEmails='["admin@company.com"]'
```

## Configuration

Edit [config.toml](config.toml) to customize your deployment:

### Key Configuration Sections

#### Project Settings
```toml
[project]
name = "myaiproject"           # Project prefix for all resources
# Fallback regions - deployment tries each in order (left to right)
locations = ["eastus", "westus2", "westeurope"]
environment = "dev"            # Environment: dev, staging, prod
# Use {location} placeholder to auto-insert selected region
resourceGroupName = "rg-myaiproject-dev-{location}"
```

**Region Fallback Feature**: The deployment automatically tests each region in the `locations` array and selects the first one that supports all your enabled services. This ensures successful deployment even if certain services aren't available in your primary region.

#### Admin Users
```toml
[admin]
emails = [
    "admin1@company.com",
    "admin2@company.com"
]
```
These users will receive:
- **Control Plane**: Contributor role at resource group level
- **Data Plane**: Full access to all service data planes (OpenAI, Cosmos DB, Storage, etc.)

#### Networking
```toml
[networking]
enabled = true                          # Enable VNet and private endpoints
vnetAddressPrefix = "10.0.0.0/16"
containerAppsSubnetPrefix = "10.0.0.0/23"
privateEndpointSubnetPrefix = "10.0.2.0/24"
sqlSubnetPrefix = "10.0.3.0/24"
```

#### Service Selection
```toml
[services.openai]
enabled = true
deployments = [
    { name = "gpt-4", model = "gpt-4", version = "2024-05-13", capacity = 10 }
]

[services.cosmosdb]
enabled = true
enableNoSQL = true
enableGremlin = true

[services.datalake]
enabled = true

[services.sqldb]
enabled = true

[services.aisearch]
enabled = true

[services.containerApps]
enabled = true

[services.containerRegistry]
enabled = true

[services.keyVault]
enabled = true

[services.monitoring]
enabled = true
```

## Resource Naming Convention

All resources follow a deterministic naming pattern:

**Pattern**: `{projectName}-{service}-{environment}-{location}`

Examples:
- OpenAI: `myai-openai-dev-eastus`
- Cosmos DB: `myai-cosmos-dev-eastus`
- SQL Server: `myai-sql-dev-eastus`
- Container Apps: `myai-containerapps-env-dev-eastus`

**Note**: Some services (Storage, ACR) have naming restrictions and remove hyphens:
- Data Lake: `myaidatalakedeveastus`
- ACR: `myaiacrdeveastus`

## RBAC Permissions

### Managed Identity Permissions

The Container Apps managed identity receives:

| Service | Role |
|---------|------|
| OpenAI | Cognitive Services OpenAI User |
| Cosmos DB | Built-in Data Contributor |
| Data Lake | Storage Blob Data Contributor |
| SQL Database | SQL DB Contributor + AAD Authentication |
| AI Search | Search Index Data Contributor, Search Service Contributor |
| Key Vault | Key Vault Secrets User |
| Container Registry | AcrPull |

### Admin User Permissions

Each admin user receives:

| Service | Roles |
|---------|-------|
| Resource Group | Contributor |
| OpenAI | Cognitive Services OpenAI Contributor |
| Cosmos DB | Account Contributor + Built-in Data Contributor |
| Data Lake | Storage Blob Data Owner |
| SQL Database | SQL DB Contributor + SQL Security Manager |
| AI Search | Search Service Contributor + Search Index Data Contributor |
| Key Vault | Key Vault Administrator |
| Container Registry | AcrPush |

## Deployment Outputs

After successful deployment, you'll receive:

- **Service Endpoints**: URLs for OpenAI, Cosmos DB, AI Search, etc.
- **Managed Identity IDs**: Client ID and Principal ID for the Container Apps identity
- **Network Information**: VNet ID, subnet IDs
- **Key Vault URI**: For secrets management

Example output:
```
Deployment Outputs:
  openAIEndpoint: https://myai-openai-dev-eastus.openai.azure.com/
  cosmosDBEndpoint: https://myai-cosmos-dev-eastus.documents.azure.com:443/
  containerAppsMIClientId: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  keyVaultUri: https://myai-kv-dev-eastus.vault.azure.net/
  sqlServerFQDN: myai-sql-dev-eastus.database.windows.net
```

## Common Operations

### Update Configuration

1. Edit `config.toml`
2. Re-run deployment (idempotent - existing resources won't be recreated)

### Add a New Service

1. Enable the service in `config.toml`:
   ```toml
   [services.aisearch]
   enabled = true
   ```
2. Re-run deployment

### Add Admin Users

1. Add email to `config.toml`:
   ```toml
   [admin]
   emails = ["existing@company.com", "new@company.com"]
   ```
2. Re-run deployment - new user will receive all permissions

### Enable Private Networking

1. Set in `config.toml`:
   ```toml
   [networking]
   enabled = true
   ```
2. Re-run deployment - private endpoints will be created

## Project Structure

```
infra-deployment/
 config.toml                    # Main configuration file
 azure.yaml                     # Azure Developer CLI config
 deploy.ps1                     # PowerShell deployment script
 deploy.sh                      # Bash deployment script
 README.md                      # This file
 infra/
     main.bicep                 # Main orchestration template
     main.parameters.json       # Parameters template
     modules/
         networking.bicep       # VNet, subnets, NSGs
         identities.bicep       # Managed identities
         monitoring.bicep       # Log Analytics, App Insights
         keyvault.bicep         # Key Vault
         openai.bicep          # Azure OpenAI Service
         cosmosdb.bicep        # Cosmos DB
         datalake.bicep        # Data Lake Gen2
         sqldb.bicep           # Azure SQL Database
         aisearch.bicep        # Azure AI Search
         containerregistry.bicep # Container Registry
         containerapps.bicep   # Container Apps Environment
         rbac.bicep            # RBAC assignments
```

## Security Best Practices

This deployment follows Azure security best practices:

1. **Network Isolation**: All services can use private endpoints
2. **Identity-Based Auth**: Managed identities instead of keys/passwords
3. **Least Privilege**: RBAC roles scoped to specific services
4. **Encryption**: All services use encryption at rest and in transit
5. **Secrets Management**: Sensitive data stored in Key Vault
6. **Soft Delete**: Key Vault has soft delete enabled (90 days)
7. **Audit Logging**: All activity logged to Log Analytics

## Troubleshooting

### Deployment Fails with "InvalidTemplate"

Check Bicep syntax:
```bash
az bicep build --file infra/main.bicep
```

### "Insufficient Permissions" Error

Ensure you have:
- Owner or Contributor role on the subscription
- User Access Administrator role (for RBAC assignments)

### Admin User Email Not Found

The admin emails must be valid Azure AD user principal names (UPNs). Check:
```bash
az ad user show --id admin@company.com
```

### Private Endpoint Issues

Ensure:
- VNet is enabled in config
- Subnet has sufficient address space
- No conflicting NSG rules

### Region Not Available for Services

The deployment has **automatic region fallback**. If deployment fails due to region availability:

1. **Check your locations array** in config.toml:
   ```toml
   locations = ["eastus", "westus2", "westeurope"]
   ```

2. **Add more fallback regions**:
   - North America: `["eastus", "westus2", "southcentralus", "centralus"]`
   - Europe: `["westeurope", "northeurope", "uksouth"]`
   - Global: `["eastus", "westus2", "westeurope", "southeastasia"]`

3. **Verify service availability**: [Azure Products by Region](https://azure.microsoft.com/global-infrastructure/services/)

4. **Disable unavailable services** in config.toml if not critical

The deployment script automatically tests each region and selects the first one that supports all enabled services.

### Service Quota Limits

Some services have regional quotas. Request increases at:
https://portal.azure.com/#blade/Microsoft_Azure_Support/HelpAndSupportBlade/quotas

## Cost Estimation

Approximate monthly costs (US East, pay-as-you-go):

| Service | SKU | Est. Cost/Month |
|---------|-----|-----------------|
| OpenAI | S0 | Pay per token (~$100-$500) |
| Cosmos DB | 400 RU/s | ~$24 |
| Data Lake | Standard LRS | ~$20/TB |
| SQL Database | S1 | ~$30 |
| AI Search | Standard | ~$250 |
| Container Apps | Consumption | Pay per use (~$10-$50) |
| Container Registry | Premium | ~$167 |
| Key Vault | Standard | ~$0.03/10K ops |
| Log Analytics | Pay-as-you-go | ~$2.30/GB |

**Total Est.**: $500-$1000/month (excluding data storage and usage)

Use the [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/) for accurate estimates.

## Support & Contributing

For issues or questions:
- Check the troubleshooting section above
- Review Azure documentation for specific services
- Open an issue in your repository

## License

This infrastructure code is provided as-is for use with Azure AI projects.

## Next Steps

After deployment:

1. **Verify Resources**: Check Azure Portal for all deployed resources
2. **Test Connectivity**: Use managed identity to connect to services
3. **Deploy Application**: Deploy your AI application to Container Apps
4. **Configure Monitoring**: Set up alerts in Application Insights
5. **Backup & DR**: Configure backup policies for stateful services

## Additional Resources

- [Azure OpenAI Service Documentation](https://learn.microsoft.com/azure/ai-services/openai/)
- [Azure Cosmos DB Documentation](https://learn.microsoft.com/azure/cosmos-db/)
- [Azure AI Search Documentation](https://learn.microsoft.com/azure/search/)
- [Azure Container Apps Documentation](https://learn.microsoft.com/azure/container-apps/)
- [Azure Developer CLI Documentation](https://learn.microsoft.com/azure/developer/azure-developer-cli/)
- [Bicep Documentation](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)
