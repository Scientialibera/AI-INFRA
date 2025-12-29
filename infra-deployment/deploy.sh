#!/bin/bash
# Bash deployment script for Azure AI Landing Zone
# This script reads config.toml and deploys the infrastructure using Azure CLI

set -e

CONFIG_FILE="${1:-config.toml}"
WHAT_IF="${2}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo -e "${RED}Azure CLI is not installed. Please install it from https://aka.ms/azure-cli${NC}"
    exit 1
fi

# Check if jq is installed for JSON parsing
if ! command -v jq &> /dev/null; then
    echo -e "${RED}jq is not installed. Please install it for JSON parsing.${NC}"
    exit 1
fi

# Check if user is logged in
if ! az account show &> /dev/null; then
    echo -e "${CYAN}Not logged in to Azure. Please log in...${NC}"
    az login
fi

# Function to parse TOML (requires Python)
parse_toml() {
    python3 -c "
import sys
import json

try:
    import tomli
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, '-m', 'pip', 'install', 'tomli'])
    import tomli

with open('$CONFIG_FILE', 'rb') as f:
    config = tomli.load(f)
    print(json.dumps(config))
"
}

echo -e "${CYAN}Loading configuration from $CONFIG_FILE...${NC}"
CONFIG_JSON=$(parse_toml)

# Extract configuration values using jq
PROJECT_NAME=$(echo $CONFIG_JSON | jq -r '.project.name')
LOCATIONS=$(echo $CONFIG_JSON | jq -r '.project.locations[]')
ENVIRONMENT=$(echo $CONFIG_JSON | jq -r '.project.environment')
RESOURCE_GROUP_TEMPLATE=$(echo $CONFIG_JSON | jq -r '.project.resourceGroupName')
ADMIN_EMAILS=$(echo $CONFIG_JSON | jq -c '.admin.emails')

# Convert locations to array
IFS=$'\n' read -d '' -r -a LOCATION_ARRAY <<< "$LOCATIONS"

echo -e "\n${YELLOW}Deployment Configuration:${NC}"
echo "  Project Name: $PROJECT_NAME"
echo "  Fallback Regions: ${LOCATION_ARRAY[@]}" | sed 's/ / -> /g'
echo "  Environment: $ENVIRONMENT"
echo "  Admin Emails: $ADMIN_EMAILS"

# Resolve admin emails to Azure AD Object IDs
echo -e "\n${CYAN}Resolving admin user Object IDs...${NC}"
ADMIN_OBJECT_IDS=()
for email in $(echo $ADMIN_EMAILS | jq -r '.[]'); do
    echo -e "  ${NC}Looking up: $email${NC}"
    USER_ID=$(az ad user show --id "$email" --query id -o tsv 2>/dev/null)
    if [ -n "$USER_ID" ]; then
        ADMIN_OBJECT_IDS+=("\"$USER_ID\"")
        echo -e "    ${GREEN} Found: $USER_ID${NC}"
    else
        echo -e "    ${RED} User not found in Azure AD: $email${NC}"
        echo -e "      ${YELLOW}Make sure the email is a valid Azure AD user principal name (UPN)${NC}"
        exit 1
    fi
done

# Convert array to JSON format
ADMIN_OBJECT_IDS_JSON="[$(IFS=,; echo "${ADMIN_OBJECT_IDS[*]}")]"
echo -e "\n${GREEN} Resolved ${#ADMIN_OBJECT_IDS[@]} admin user(s)${NC}"

# Function to test if a region supports required services
test_region_availability() {
    local region=$1
    local openai_enabled=$(echo $CONFIG_JSON | jq -r '.services.openai.enabled')
    local cosmosdb_enabled=$(echo $CONFIG_JSON | jq -r '.services.cosmosdb.enabled')
    local containerapps_enabled=$(echo $CONFIG_JSON | jq -r '.services.containerApps.enabled')

    echo -e "\n  ${CYAN}Testing region: $region...${NC}"

    # Check OpenAI availability
    if [ "$openai_enabled" = "true" ]; then
        echo -e "    ${NC}Checking OpenAI availability...${NC}"
        local openai_locations=$(az provider show --namespace Microsoft.CognitiveServices --query "resourceTypes[?resourceType=='accounts'].locations[]" -o json | jq -r '.[]')
        if ! echo "$openai_locations" | grep -qi "$region"; then
            echo -e "    ${YELLOW} OpenAI not available in $region${NC}"
            return 1
        fi
    fi

    # Check Cosmos DB availability
    if [ "$cosmosdb_enabled" = "true" ]; then
        echo -e "    ${NC}Checking Cosmos DB availability...${NC}"
        local cosmos_locations=$(az provider show --namespace Microsoft.DocumentDB --query "resourceTypes[?resourceType=='databaseAccounts'].locations[]" -o json | jq -r '.[]')
        if ! echo "$cosmos_locations" | grep -qi "$region"; then
            echo -e "    ${YELLOW} Cosmos DB not available in $region${NC}"
            return 1
        fi
    fi

    # Check Container Apps availability
    if [ "$containerapps_enabled" = "true" ]; then
        echo -e "    ${NC}Checking Container Apps availability...${NC}"
        local containerapps_locations=$(az provider show --namespace Microsoft.App --query "resourceTypes[?resourceType=='managedEnvironments'].locations[]" -o json | jq -r '.[]')
        if ! echo "$containerapps_locations" | grep -qi "$region"; then
            echo -e "    ${YELLOW} Container Apps not available in $region${NC}"
            return 1
        fi
    fi

    echo -e "    ${GREEN} Region $region supports all required services${NC}"
    return 0
}

# Find the first available region
echo -e "\n${YELLOW}Testing region availability...${NC}"
SELECTED_LOCATION=""
for location in "${LOCATION_ARRAY[@]}"; do
    if test_region_availability "$location"; then
        SELECTED_LOCATION="$location"
        echo -e "\n${GREEN} Selected region: $SELECTED_LOCATION${NC}"
        break
    fi
done

if [ -z "$SELECTED_LOCATION" ]; then
    echo -e "\n${RED} None of the specified regions support all required services!${NC}"
    echo -e "  ${YELLOW}Tried regions: ${LOCATION_ARRAY[@]}${NC}"
    echo -e "  ${YELLOW}Please update config.toml with different regions or disable some services.${NC}"
    exit 1
fi

# Update resource group name with selected location
RESOURCE_GROUP=$(echo "$RESOURCE_GROUP_TEMPLATE" | sed "s/{location}/$SELECTED_LOCATION/")
if [[ ! "$RESOURCE_GROUP" =~ $SELECTED_LOCATION ]]; then
    # If no {location} placeholder, append it
    RESOURCE_GROUP="$RESOURCE_GROUP_TEMPLATE-$SELECTED_LOCATION"
fi

echo -e "\n${YELLOW}Final Configuration:${NC}"
echo "  Selected Region: $SELECTED_LOCATION"
echo "  Resource Group: $RESOURCE_GROUP"

# Create resource group if it doesn't exist
echo -e "\n${CYAN}Ensuring resource group exists...${NC}"
RG_EXISTS=$(az group exists --name $RESOURCE_GROUP)
if [ "$RG_EXISTS" = "false" ]; then
    echo -e "${GREEN}Creating resource group: $RESOURCE_GROUP${NC}"
    if [ "$WHAT_IF" != "--what-if" ]; then
        az group create --name $RESOURCE_GROUP --location $SELECTED_LOCATION
    fi
else
    echo -e "${GREEN}Resource group already exists: $RESOURCE_GROUP${NC}"
fi

# Build parameters JSON
PARAMS_JSON=$(cat <<EOF
{
  "projectName": {"value": "$PROJECT_NAME"},
  "location": {"value": "$SELECTED_LOCATION"},
  "environment": {"value": "$ENVIRONMENT"},
  "adminEmails": {"value": $ADMIN_OBJECT_IDS_JSON},
  "enableVNet": {"value": $(echo $CONFIG_JSON | jq '.networking.enabled')},
  "vnetAddressPrefix": {"value": "$(echo $CONFIG_JSON | jq -r '.networking.vnetAddressPrefix')"},
  "containerAppsSubnetPrefix": {"value": "$(echo $CONFIG_JSON | jq -r '.networking.containerAppsSubnetPrefix')"},
  "privateEndpointSubnetPrefix": {"value": "$(echo $CONFIG_JSON | jq -r '.networking.privateEndpointSubnetPrefix')"},
  "sqlSubnetPrefix": {"value": "$(echo $CONFIG_JSON | jq -r '.networking.sqlSubnetPrefix')"},
  "enableOpenAI": {"value": $(echo $CONFIG_JSON | jq '.services.openai.enabled')},
  "enableCosmosDB": {"value": $(echo $CONFIG_JSON | jq '.services.cosmosdb.enabled')},
  "enableDataLake": {"value": $(echo $CONFIG_JSON | jq '.services.datalake.enabled')},
  "enableSQLDB": {"value": $(echo $CONFIG_JSON | jq '.services.sqldb.enabled')},
  "enableAISearch": {"value": $(echo $CONFIG_JSON | jq '.services.aisearch.enabled')},
  "enableContainerApps": {"value": $(echo $CONFIG_JSON | jq '.services.containerApps.enabled')},
  "enableContainerRegistry": {"value": $(echo $CONFIG_JSON | jq '.services.containerRegistry.enabled')},
  "enableKeyVault": {"value": $(echo $CONFIG_JSON | jq '.services.keyVault.enabled')},
  "enableMonitoring": {"value": $(echo $CONFIG_JSON | jq '.services.monitoring.enabled')},
  "openAIDeployments": {"value": $(echo $CONFIG_JSON | jq -c '.services.openai.deployments')},
  "cosmosEnableNoSQL": {"value": $(echo $CONFIG_JSON | jq '.services.cosmosdb.enableNoSQL')},
  "cosmosEnableGremlin": {"value": $(echo $CONFIG_JSON | jq '.services.cosmosdb.enableGremlin')},
  "cosmosConsistencyLevel": {"value": "$(echo $CONFIG_JSON | jq -r '.services.cosmosdb.consistencyLevel')"},
  "sqlDatabaseSku": {"value": "$(echo $CONFIG_JSON | jq -r '.services.sqldb.databaseSku')"},
  "sqlAdminUsername": {"value": "$(echo $CONFIG_JSON | jq -r '.services.sqldb.adminUsername')"},
  "sqlAllowedIpRanges": {"value": $(echo $CONFIG_JSON | jq -c '.services.sqldb.allowedIpRanges')},
  "aiSearchSku": {"value": "$(echo $CONFIG_JSON | jq -r '.services.aisearch.sku')"},
  "containerRegistrySku": {"value": "$(echo $CONFIG_JSON | jq -r '.services.containerRegistry.sku')"},
  "dataLakeSku": {"value": "$(echo $CONFIG_JSON | jq -r '.services.datalake.sku')"},
  "tags": {"value": $(echo $CONFIG_JSON | jq -c '.tags')}
}
EOF
)

# Write parameters to temporary file
TEMP_PARAMS_FILE=$(mktemp)
echo $PARAMS_JSON | jq '.' > $TEMP_PARAMS_FILE

echo -e "\n${CYAN}Deploying infrastructure...${NC}"
echo -e "${YELLOW}This may take 15-30 minutes depending on the services enabled...${NC}"

if [ "$WHAT_IF" = "--what-if" ]; then
    echo -e "\n${YELLOW}[WHAT-IF MODE] Would deploy with these parameters:${NC}"
    cat $TEMP_PARAMS_FILE | jq '.'
else
    # Deploy using Azure CLI
    DEPLOYMENT_NAME="ai-landing-zone-$(date +%Y%m%d-%H%M%S)"

    az deployment group create \
        --name $DEPLOYMENT_NAME \
        --resource-group $RESOURCE_GROUP \
        --template-file infra/main.bicep \
        --parameters "@$TEMP_PARAMS_FILE" \
        --verbose

    if [ $? -eq 0 ]; then
        echo -e "\n${GREEN} Deployment completed successfully!${NC}"

        # Get outputs
        echo -e "\n${CYAN}Retrieving deployment outputs...${NC}"
        OUTPUTS=$(az deployment group show \
            --name $DEPLOYMENT_NAME \
            --resource-group $RESOURCE_GROUP \
            --query properties.outputs \
            --output json)

        echo -e "\n${YELLOW}Deployment Outputs:${NC}"
        echo $OUTPUTS | jq -r 'to_entries[] | "  \(.key): \(.value.value)"'
    else
        echo -e "\n${RED} Deployment failed!${NC}"
        exit 1
    fi
fi

# Clean up temp file
rm -f $TEMP_PARAMS_FILE

echo -e "\n${CYAN}Deployment script completed.${NC}"
