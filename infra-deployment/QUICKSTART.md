# Quick Start Guide - Azure AI Landing Zone

Deploy your enterprise AI infrastructure in 30 minutes with automatic region fallback!

## What You'll Get

### Core Services
-  Azure OpenAI (GPT-4, GPT-3.5, embeddings) with content filtering
-  Cosmos DB (NoSQL + Graph) with serverless & geo-replication options
-  Data Lake Gen2 for storage
-  Azure SQL Database with zone redundancy option
-  Azure AI Search with semantic/vector search
-  Container Apps environment with Dapr & zone redundancy
-  Container Registry with geo-replication
-  Key Vault for secrets (stores SQL password automatically)
-  Full monitoring setup with configurable retention
-  Secure networking with private DNS zone VNet links
-  **Automatic region fallback** for resilient deployment

### Optional Services (NEW)
-  API Management - API gateway for AI services
-  Azure Front Door - Global CDN with WAF
-  Redis Cache - For chat history/caching
-  Azure Policy - Enforce required tags

---

## 5-Minute Setup

### Step 1: Configure (2 minutes)

1. Copy the example configuration:
   ```powershell
   Copy-Item config.example.toml config.toml
   ```

2. Edit `config.toml` - **minimum required changes**:
   ```toml
   [project]
   name = "yourproject"
   locations = ["eastus", "westus2", "westeurope"]

   [admin]
   emails = ["your.email@company.com"]
   ```

3. That's it! The deployment will automatically:
   - Resolve your email to Azure AD Object ID
   - Test each region in order
   - Select the first one that supports all services
   - Deploy everything with proper permissions

### Step 2: Deploy (3 minutes)

**Windows (PowerShell):**
```powershell
.\deploy.ps1
```

**Linux/Mac (Bash):**
```bash
chmod +x deploy.sh
./deploy.sh
```

**Watch the magic happen:**
```
Loading configuration from config.toml...

Deployment Configuration:
  Project Name: yourproject
  Fallback Regions: eastus -> westus2 -> westeurope
  Environment: dev
  Admin Emails: your.email@company.com

Resolving admin user Object IDs...
  Looking up: your.email@company.com
     Found: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

Testing region availability...
  Testing region: eastus...
    Checking OpenAI availability...
    Checking Cosmos DB availability...
    Checking Container Apps availability...
     Region eastus supports all required services

 Selected region: eastus

Deploying infrastructure...
```

Wait 15-30 minutes for completion.

---

## Configuration Options

### Enable Optional Services

```toml
# API Management for API gateway
[services.apim]
enabled = true
publisherEmail = "api-admin@company.com"
publisherName = "Your Company"
sku = "Developer"

# Azure Front Door with WAF
[services.frontDoor]
enabled = true
enableWaf = true

# Redis Cache for chat history
[services.redis]
enabled = true
sku = "Standard"
capacity = 1

# Azure Policy for tag enforcement
[policy]
enabled = true
requiredTags = ["reason", "purpose"]
enforcementMode = "Default"  # "Default" = Deny, "DoNotEnforce" = Audit
```

### Enhanced Service Options

```toml
# OpenAI with content filtering
[services.openai]
enabled = true
contentFilterPolicy = "default"
deployments = [
    { name = "gpt-4", model = "gpt-4", version = "2024-05-13", capacity = 10 },
    { name = "gpt-35-turbo", model = "gpt-35-turbo", version = "0613", capacity = 10 }
]

# Cosmos DB with advanced features
[services.cosmosdb]
enabled = true
enableNoSQL = true
enableGremlin = true
consistencyLevel = "Session"
enableServerless = false        # Cost-effective for dev
enableAnalyticalStorage = false # For analytics workloads
additionalRegions = []          # e.g., ["westus2", "westeurope"]

# SQL with zone redundancy
[services.sqldb]
enabled = true
databaseSku = "S1"
zoneRedundant = false  # Set true for production

# AI Search with semantic/vector
[services.aisearch]
enabled = true
sku = "standard"
replicaCount = 1
partitionCount = 1
semanticSearchTier = "free"  # or "standard"

# Container Apps with Dapr
[services.containerApps]
enabled = true
enableDapr = false       # Enable for microservices
zoneRedundant = false    # Enable for production

# Container Registry with geo-replication
[services.containerRegistry]
enabled = true
sku = "Premium"
geoReplicationLocations = []  # e.g., ["westus2", "westeurope"]

# Key Vault configuration
[services.keyVault]
enabled = true
sku = "standard"
softDeleteRetentionInDays = 90

# Monitoring with custom retention
[services.monitoring]
enabled = true
retentionInDays = 30  # 30-730 days
```

### Required Tags (with Policy)

```toml
[tags]
Environment = "Development"
ManagedBy = "AzureDeveloperCLI"
Project = "AI-LandingZone"
reason = "AI Landing Zone Infrastructure"  # Required by policy
purpose = "Enterprise AI Platform"         # Required by policy
```

---

## Region Fallback Feature 

### How It Works

The deployment automatically:
1. **Tests each region** in your `locations` array (left to right)
2. **Checks availability** of enabled services
3. **Selects the first** region that supports everything
4. **Deploys there** with no manual intervention

### Recommended Region Sets

**North America (Best for US clients):**
```toml
locations = ["eastus", "westus2", "southcentralus", "centralus"]
```

**Europe (Best for EU clients):**
```toml
locations = ["westeurope", "northeurope", "uksouth", "francecentral"]
```

**Global (Maximum redundancy):**
```toml
locations = ["eastus", "westus2", "westeurope", "southeastasia", "australiaeast"]
```

---

## What Happens During Deployment

### Phase 1: Preparation (2-3 minutes)
```
 Loading configuration
 Resolving admin emails to Azure AD Object IDs
 Testing region availability...
 Selected region: eastus
 Creating resource group
```

### Phase 2: Infrastructure Deployment (15-30 minutes)
```
 Deploying networking (VNet, subnets, NSGs)
 Deploying monitoring (Log Analytics, App Insights)
 Creating managed identity
 Deploying Key Vault
 Deploying OpenAI (with model deployments)
 Deploying Cosmos DB (with SQL role assignments)
 Deploying Data Lake (with private DNS links)
 Deploying SQL Database (password stored in Key Vault)
 Deploying AI Search
 Deploying Container Apps
 Deploying Container Registry
 Deploying APIM (if enabled)
 Deploying Front Door (if enabled)
 Deploying Redis (if enabled)
 Configuring Azure Policy (if enabled)
 Configuring RBAC (admin permissions)
 Creating private endpoints with VNet-linked DNS zones
```

### Phase 3: Outputs
```
Deployment Outputs:
  selectedRegion: eastus
  openAIEndpoint: https://yourproject-openai-dev.openai.azure.com/
  cosmosDBEndpoint: https://yourproject-cosmos-dev.documents.azure.com/
  containerAppsMIClientId: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  keyVaultUri: https://yourproject-kv-dev.vault.azure.net/
  sqlServerFQDN: yourproject-sql-dev.database.windows.net
  apimGatewayUrl: https://yourproject-apim-dev.azure-api.net/
  frontDoorEndpoint: yourproject-fd-dev-endpoint.azurefd.net
  redisHostName: yourproject-redis-dev.redis.cache.windows.net
```

---

## Key Features Explained

### SQL Password in Key Vault
SQL admin password is **automatically generated** and stored in Key Vault:
- Secret name: `sql-admin-password`
- Connection string: `sql-connection-string`

No need to manage passwords manually!

### Private DNS Zone VNet Links
When VNet is enabled, all private DNS zones are automatically linked to the VNet:
- Enables proper name resolution for private endpoints
- No manual DNS configuration needed
- Supports all services (OpenAI, Cosmos DB, SQL, Storage, etc.)

### Content Filtering for OpenAI
Configure responsible AI content filters:
```toml
[services.openai]
contentFilterPolicy = "default"  # or custom policy name
deployments = [
    { name = "gpt-4", model = "gpt-4", version = "2024-05-13", capacity = 10, raiPolicyName = "custom-filter" }
]
```

### Cosmos DB Data Plane RBAC
Cosmos DB uses its own SQL Role Assignment system (not Azure RBAC) for data plane access:
- Proper data contributor role assigned to managed identity
- Admin users get both control plane AND data plane access

---

## Verify Deployment

1. **Azure Portal**: Navigate to your resource group
2. **Check Services**: All enabled services should show "Running"
3. **Verify Secrets**: Check Key Vault for SQL password
4. **Test DNS**: Private endpoints should resolve correctly
5. **View Logs**: Check Log Analytics for activity

---

## Next Steps

### 1. Test OpenAI

```python
from azure.identity import DefaultAzureCredential
from openai import AzureOpenAI

credential = DefaultAzureCredential()
endpoint = "YOUR_OPENAI_ENDPOINT"  # From deployment outputs

client = AzureOpenAI(
    azure_endpoint=endpoint,
    api_version="2024-02-01",
    azure_ad_token_provider=lambda: credential.get_token(
        "https://cognitiveservices.azure.com/.default"
    ).token
)

response = client.chat.completions.create(
    model="gpt-4",
    messages=[{"role": "user", "content": "Hello!"}]
)
print(response.choices[0].message.content)
```

### 2. Get SQL Password from Key Vault

```bash
az keyvault secret show \
  --vault-name <YOUR_KV_NAME> \
  --name sql-admin-password \
  --query value -o tsv
```

### 3. Deploy Your Container

```bash
# Build and push
az acr build \
  --registry <YOUR_ACR_NAME> \
  --image myapp:v1 \
  .

# Deploy to Container Apps
az containerapp create \
  --name myapp \
  --resource-group <YOUR_RG_NAME> \
  --environment <YOUR_CONTAINERAPP_ENV> \
  --image <YOUR_ACR_NAME>.azurecr.io/myapp:v1 \
  --target-port 80
```

---

## Troubleshooting

### All Regions Fail
If you see:
```
 None of the specified regions support all required services!
```

**Solutions:**
1. Add more regions to your config
2. Disable services you don't need
3. Check [Azure Products by Region](https://azure.microsoft.com/global-infrastructure/services/)

### Admin Email Not Found
```
 User not found in Azure AD: user@company.com
```

**Solution**: Ensure the email is a valid Azure AD user principal name (UPN)

### Permission Denied
Ensure you have:
- Contributor role on subscription
- User Access Administrator role (for RBAC)

### Private Endpoint DNS Issues
If private endpoints aren't resolving:
1. Verify VNet is enabled in config
2. Check that DNS zone VNet links exist
3. Restart your client/VM to refresh DNS cache

---

## Clean Up

Delete everything:
```bash
az group delete --name <YOUR_RG_NAME> --yes --no-wait
```

 **Warning**: This is permanent and deletes all data!

---

## Learn More

- **Full Documentation**: [README.md](README.md)
- **Permissions Details**: [PERMISSIONS_MATRIX.md](PERMISSIONS_MATRIX.md)
- **Future Improvements**: [FUTURE_IMPROVEMENTS.md](FUTURE_IMPROVEMENTS.md)

---

## Success Checklist

After deployment, you should have:

-  All services deployed in selected region
-  Managed identity with permissions configured
-  Your admin account has full access (via Object ID)
-  Private networking with DNS zone VNet links (if enabled)
-  SQL password stored in Key Vault
-  Monitoring collecting logs
-  Service endpoints available
-  APIM/Front Door/Redis (if enabled)
-  Azure Policy enforcing tags (if enabled)

---

**Ready to deploy?** Just run `.\deploy.ps1` (Windows) or `./deploy.sh` (Linux/Mac) and you're live in 30 minutes! 

The automatic region fallback ensures you'll never fail due to regional service availability. Just specify your preferred regions and let the deployment handle the rest!
