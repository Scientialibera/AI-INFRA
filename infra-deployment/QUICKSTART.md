# Quick Start Guide - Azure AI Landing Zone

Deploy your enterprise AI infrastructure in 30 minutes with automatic region fallback!

## What You'll Get

-  Azure OpenAI (GPT-4, GPT-3.5, embeddings)
-  Cosmos DB (NoSQL + Graph)
-  Data Lake Gen2 for storage
-  Azure SQL Database
-  Azure AI Search
-  Container Apps environment
-  Container Registry
-  Key Vault for secrets
-  Full monitoring setup
-  Secure networking (optional)
-  **Automatic region fallback** for resilient deployment

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
   # Add multiple regions for automatic fallback
   locations = ["eastus", "westus2", "westeurope"]

   [admin]
   emails = ["your.email@company.com"]
   ```

3. That's it! The deployment will automatically:
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

## Region Fallback Feature 

### How It Works

The deployment automatically:
1. **Tests each region** in your `locations` array (left to right)
2. **Checks availability** of enabled services (OpenAI, Cosmos DB, Container Apps, etc.)
3. **Selects the first** region that supports everything
4. **Deploys there** with no manual intervention

### Example Scenarios

**Scenario 1: OpenAI Not Available in Primary Region**
```toml
locations = ["canadaeast", "eastus", "westus2"]
```
Output:
```
Testing region: canadaeast...
   OpenAI not available in canadaeast
Testing region: eastus...
   Region eastus supports all required services
 Selected region: eastus
```

**Scenario 2: Multiple Services Check**
```toml
locations = ["southcentralus", "westeurope", "eastus"]
```
The script checks each region for:
- OpenAI availability (if enabled)
- Cosmos DB availability (if enabled)
- Container Apps availability (if enabled)
- Other services as configured

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

**Cost-Optimized (Fewer regions, faster decision):**
```toml
locations = ["eastus", "westus2"]
```

## Customization Examples

### Minimal Setup (Lower Cost)

```toml
[project]
name = "myai"
locations = ["eastus", "westus2"]

[networking]
enabled = false  # Skip VNet for simpler setup

[services.openai]
enabled = true

[services.datalake]
enabled = true

# Disable what you don't need
[services.cosmosdb]
enabled = false

[services.sqldb]
enabled = false

[services.aisearch]
enabled = false
```

**Monthly Cost**: ~$50-100

### Full Stack (Production Ready)

```toml
[project]
name = "prodai"
locations = ["eastus", "westus2", "westeurope"]
environment = "prod"

[networking]
enabled = true  # Secure private networking

# All services enabled with default settings
```

**Monthly Cost**: ~$500-1000

### Specific Region Requirements

If you need a specific region for compliance:

```toml
# Europe-only for GDPR
locations = ["westeurope", "northeurope", "francecentral"]

# US-only for data residency
locations = ["eastus", "westus2", "southcentralus"]

# Asia-Pacific only
locations = ["southeastasia", "australiaeast", "japaneast"]
```

## What Happens During Deployment

### Phase 1: Region Selection (2-3 minutes)
```
 Loading configuration
 Testing region availability...
  Testing region: eastus...
    Checking OpenAI availability...
    Checking Cosmos DB availability...
    Checking Container Apps availability...
 Selected region: eastus
 Creating resource group: rg-myai-dev-eastus
```

### Phase 2: Infrastructure Deployment (15-30 minutes)
```
 Deploying networking (VNet, subnets, NSGs)
 Deploying monitoring (Log Analytics, App Insights)
 Creating managed identity
 Deploying OpenAI (with model deployments)
 Deploying Cosmos DB
 Deploying Data Lake
 Deploying SQL Database
 Deploying AI Search
 Deploying Container Apps
 Deploying Container Registry
 Deploying Key Vault
 Configuring RBAC (admin permissions)
 Creating private endpoints
```

### Phase 3: Outputs
```
Deployment Outputs:
  selectedRegion: eastus
  openAIEndpoint: https://myai-openai-dev-eastus.openai.azure.com/
  cosmosDBEndpoint: https://myai-cosmos-dev-eastus.documents.azure.com/
  containerAppsMIClientId: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  keyVaultUri: https://myai-kv-dev-eastus.vault.azure.net/
```

## Verify Deployment

1. **Azure Portal**: Navigate to your resource group
2. **Check Services**: All enabled services should show "Running"
3. **Test Access**: Use the managed identity to connect
4. **View Logs**: Check Log Analytics for activity

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

### 2. Deploy Your Container

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

### 3. Store Secrets

```bash
az keyvault secret set \
  --vault-name <YOUR_KV_NAME> \
  --name ApiKey \
  --value "your-secret"
```

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

### Quota Exceeded

If OpenAI deployment fails with quota error:
1. Try a different region from your list
2. Request quota increase in Azure Portal
3. Reduce `capacity` in OpenAI deployments config

### Permission Denied

Ensure you have:
- Contributor role on subscription
- User Access Administrator role (for RBAC)

Check your roles:
```bash
az role assignment list --assignee $(az ad signed-in-user show --query id -o tsv)
```

### Slow Deployment

First deployment takes 20-30 minutes (normal). Services that take longest:
- OpenAI: 5-10 minutes (model deployments)
- Cosmos DB: 3-5 minutes
- SQL Database: 3-5 minutes

## Cost Monitoring

### View Current Costs

```bash
az consumption usage list \
  --start-date $(date -d "1 month ago" +%Y-%m-%d) \
  --end-date $(date +%Y-%m-%d)
```

### Set Budget Alert

1. Azure Portal → Cost Management
2. Create budget for your resource group
3. Set alerts at 80% and 100%

## Clean Up

Delete everything:
```bash
az group delete --name <YOUR_RG_NAME> --yes --no-wait
```

 **Warning**: This is permanent and deletes all data!

## Advanced: Region-Specific Optimization

### Optimize for Latency

Put regions closest to your users first:
```toml
# Users in US East Coast
locations = ["eastus", "centralus", "westus2"]

# Users in Western Europe
locations = ["westeurope", "northeurope", "uksouth"]
```

### Optimize for Cost

Some regions have lower costs:
```toml
# Generally lower-cost US regions
locations = ["southcentralus", "centralus", "eastus"]
```

### Optimize for Compliance

```toml
# GDPR - Europe only
locations = ["westeurope", "northeurope"]

# FedRAMP - US Gov regions
locations = ["usgovvirginia", "usgovarizona"]
```

## Learn More

- **Full Documentation**: [README.md](README.md)
- **Architecture Details**: [ARCHITECTURE.md](ARCHITECTURE.md)
- **Deployment Summary**: [DEPLOYMENT_SUMMARY.md](DEPLOYMENT_SUMMARY.md)

## Success Checklist

After deployment, you should have:

-  All services deployed in selected region
-  Managed identity with permissions configured
-  Your admin account has full access
-  Private networking (if enabled)
-  Monitoring collecting logs
-  Service endpoints available

## Common Questions

**Q: Can I add more regions after deployment?**
A: Yes! Just update config.toml and redeploy. The deployment is idempotent.

**Q: What if I need a service not available in any of my regions?**
A: Either add more regions, or disable that service and use an alternative.

**Q: Does it cost extra to list multiple fallback regions?**
A: No! Only the selected region is deployed. Others are just tested.

**Q: Can I force a specific region?**
A: Yes, just put one region in the locations array: `locations = ["westeurope"]`

**Q: What happens if my primary region becomes unavailable later?**
A: The infrastructure stays in the deployed region. To move, update config and redeploy.

---

**Ready to deploy?** Just run `.\deploy.ps1` (Windows) or `./deploy.sh` (Linux/Mac) and you're live in 30 minutes! 

The automatic region fallback ensures you'll never fail due to regional service availability. Just specify your preferred regions and let the deployment handle the rest!
