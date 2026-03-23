#!/bin/bash
# Bash deployment script for Azure AI Landing Zone
# This script reads config.toml and deploys the infrastructure using Azure CLI

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$REPO_ROOT/config/config.toml"
WHAT_IF=false

for arg in "$@"; do
    case "$arg" in
        --what-if)
            WHAT_IF=true
            ;;
        -*)
            echo "Unknown option: $arg"
            echo "Usage: ./scripts/deploy.sh [config-file] [--what-if]"
            exit 1
            ;;
        *)
            if [[ "$arg" = /* ]]; then
                CONFIG_FILE="$arg"
            else
                CONFIG_FILE="$REPO_ROOT/$arg"
            fi
            ;;
    esac
done

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

if ! command -v az >/dev/null 2>&1; then
    echo -e "${RED}Azure CLI is not installed. Please install it from https://aka.ms/azure-cli${NC}"
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo -e "${RED}jq is not installed. Please install it for JSON parsing.${NC}"
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1 && ! command -v python >/dev/null 2>&1; then
    echo -e "${RED}Python is required to parse TOML reliably. Install Python 3.11+.${NC}"
    exit 1
fi

if ! az account show >/dev/null 2>&1; then
    echo -e "${CYAN}Not logged in to Azure. Please log in...${NC}"
    az login
fi

parse_toml() {
    local python_cmd
    if command -v python >/dev/null 2>&1; then
        python_cmd="python"
    else
        python_cmd="python3"
    fi

    "$python_cmd" -c "
import json
import pathlib
import sys

path = pathlib.Path(r'''$CONFIG_FILE''')
if not path.exists():
    print('CONFIG_NOT_FOUND')
    sys.exit(3)

try:
    import tomllib as toml
except ModuleNotFoundError:
    try:
        import tomli as toml
    except ModuleNotFoundError:
        print('TOML_PARSER_MISSING')
        sys.exit(2)

with path.open('rb') as f:
    print(json.dumps(toml.load(f)))
"
}

echo -e "${CYAN}Loading configuration from $CONFIG_FILE...${NC}"
CONFIG_JSON="$(parse_toml)"

if [ "$CONFIG_JSON" = "CONFIG_NOT_FOUND" ]; then
    echo -e "${RED}Config file not found: $CONFIG_FILE${NC}"
    exit 1
fi

if [ "$CONFIG_JSON" = "TOML_PARSER_MISSING" ]; then
    echo -e "${RED}Python TOML support is missing. Install Python 3.11+ or run 'python -m pip install --user tomli'.${NC}"
    exit 1
fi

PROJECT_NAME="$(echo "$CONFIG_JSON" | jq -r '.project.name')"
RESOURCE_GROUP_TEMPLATE="$(echo "$CONFIG_JSON" | jq -r '.project.resourceGroupName')"

mapfile -t LOCATION_ARRAY < <(echo "$CONFIG_JSON" | jq -r '.project.locations[]')

DEPLOYMENT_PREFIXES_JSON="$(echo "$CONFIG_JSON" | jq -c '
    if .project.prefixes? != null then
      if (.project.prefixes | type) == "array" then .project.prefixes else [.project.prefixes] end
    elif .project.prefix? != null then
      [.project.prefix]
    else
      [.project.environment]
    end
    | map(tostring | gsub("^\\s+|\\s+$"; ""))
    | map(select(length > 0))
    | unique
')"

mapfile -t DEPLOYMENT_PREFIXES < <(echo "$DEPLOYMENT_PREFIXES_JSON" | jq -r '.[]')
if [ "${#DEPLOYMENT_PREFIXES[@]}" -eq 0 ]; then
    echo -e "${RED}No deployment prefixes found. Set project.prefixes (array), project.prefix (string), or project.environment.${NC}"
    exit 1
fi

ADMIN_EMAILS_JSON="$(echo "$CONFIG_JSON" | jq -c '.admin.emails')"

echo -e "\n${YELLOW}Deployment Configuration:${NC}"
echo "  Project Name: $PROJECT_NAME"
echo "  Fallback Regions: $(IFS=' -> '; echo "${LOCATION_ARRAY[*]}")"
echo "  Deployment Prefixes: $(IFS=', '; echo "${DEPLOYMENT_PREFIXES[*]}")"
echo "  Admin Emails: $ADMIN_EMAILS_JSON"

echo -e "\n${CYAN}Resolving admin user Object IDs...${NC}"
ADMIN_OBJECT_IDS=()
while IFS= read -r email; do
    echo -e "  Looking up: $email"
    user_id="$(az ad user show --id "$email" --query id -o tsv 2>/dev/null || true)"
    if [ -n "$user_id" ]; then
        ADMIN_OBJECT_IDS+=("$user_id")
        echo -e "    ${GREEN}Found: $user_id${NC}"
    else
        echo -e "    ${RED}User not found in Azure AD: $email${NC}"
        exit 1
    fi
done < <(echo "$ADMIN_EMAILS_JSON" | jq -r '.[]')

ADMIN_OBJECT_IDS_JSON="$(printf '%s\n' "${ADMIN_OBJECT_IDS[@]}" | jq -R . | jq -s .)"
echo -e "\n${GREEN}Resolved ${#ADMIN_OBJECT_IDS[@]} admin user(s)${NC}"

normalize_region() {
    echo "$1" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]'
}

test_region_availability() {
    local region="$1"
    local normalized_region
    normalized_region="$(normalize_region "$region")"

    echo -e "\n  ${CYAN}Testing region: $region...${NC}"

    local openai_enabled cosmos_enabled containerapps_enabled
    openai_enabled="$(echo "$CONFIG_JSON" | jq -r '.services.openai.enabled // false')"
    cosmos_enabled="$(echo "$CONFIG_JSON" | jq -r '.services.cosmosdb.enabled // false')"
    containerapps_enabled="$(echo "$CONFIG_JSON" | jq -r '.services.containerApps.enabled // false')"

    if [ "$openai_enabled" = "true" ]; then
        echo "    Checking OpenAI availability..."
        local openai_locations
        openai_locations="$(az provider show --namespace Microsoft.CognitiveServices --query "resourceTypes[?resourceType=='accounts'].locations[]" -o json | jq -r '.[]? | ascii_downcase | gsub("\\s"; "")')"
        if ! echo "$openai_locations" | grep -Fxq "$normalized_region"; then
            echo -e "    ${YELLOW}OpenAI not available in $region${NC}"
            return 1
        fi
    fi

    if [ "$cosmos_enabled" = "true" ]; then
        echo "    Checking Cosmos DB availability..."
        local cosmos_locations
        cosmos_locations="$(az provider show --namespace Microsoft.DocumentDB --query "resourceTypes[?resourceType=='databaseAccounts'].locations[]" -o json | jq -r '.[]? | ascii_downcase | gsub("\\s"; "")')"
        if ! echo "$cosmos_locations" | grep -Fxq "$normalized_region"; then
            echo -e "    ${YELLOW}Cosmos DB not available in $region${NC}"
            return 1
        fi
    fi

    if [ "$containerapps_enabled" = "true" ]; then
        echo "    Checking Container Apps availability..."
        local containerapps_locations
        containerapps_locations="$(az provider show --namespace Microsoft.App --query "resourceTypes[?resourceType=='managedEnvironments'].locations[]" -o json | jq -r '.[]? | ascii_downcase | gsub("\\s"; "")')"
        if ! echo "$containerapps_locations" | grep -Fxq "$normalized_region"; then
            echo -e "    ${YELLOW}Container Apps not available in $region${NC}"
            return 1
        fi
    fi

    echo -e "    ${GREEN}Region $region supports all required services${NC}"
    return 0
}

echo -e "\n${YELLOW}Testing region availability...${NC}"
SELECTED_LOCATION=""
for location in "${LOCATION_ARRAY[@]}"; do
    if test_region_availability "$location"; then
        SELECTED_LOCATION="$location"
        echo -e "\n${GREEN}Selected region: $SELECTED_LOCATION${NC}"
        break
    fi
done

if [ -z "$SELECTED_LOCATION" ]; then
    echo -e "\n${RED}None of the specified regions support all required services!${NC}"
    echo -e "${YELLOW}Tried regions: ${LOCATION_ARRAY[*]}${NC}"
    exit 1
fi

get_bicep_executable() {
    if command -v bicep >/dev/null 2>&1; then
        command -v bicep
        return
    fi

    if [ -n "${LOCALAPPDATA:-}" ]; then
        local winget_bicep
        winget_bicep="$LOCALAPPDATA/Microsoft/WinGet/Packages/Microsoft.Bicep_Microsoft.Winget.Source_8wekyb3d8bbwe/bicep.exe"
        if [ -f "$winget_bicep" ]; then
            echo "$winget_bicep"
            return
        fi
    fi

    echo ""
}

BICEP_EXE="$(get_bicep_executable)"
if [ -z "$BICEP_EXE" ]; then
    echo -e "${RED}Bicep CLI not found. Install Bicep or ensure it is on PATH.${NC}"
    exit 1
fi

TEMP_TEMPLATE_FILE="$(mktemp)"
TEMP_TEMPLATE_FILE="${TEMP_TEMPLATE_FILE%.*}.json"

echo -e "\n${CYAN}Compiling Bicep template...${NC}"
"$BICEP_EXE" build "$REPO_ROOT/infra/main.bicep" --outfile "$TEMP_TEMPLATE_FILE"

echo -e "\n${CYAN}Deploying infrastructure...${NC}"
echo -e "${YELLOW}This may take 15-30 minutes depending on the services enabled...${NC}"

for prefix in "${DEPLOYMENT_PREFIXES[@]}"; do
    environment="$prefix"
    resource_group="$RESOURCE_GROUP_TEMPLATE"

    has_location_placeholder=false
    has_prefix_placeholder=false

    if [[ "$resource_group" == *"{location}"* ]]; then
        has_location_placeholder=true
    fi
    if [[ "$resource_group" == *"{prefix}"* || "$resource_group" == *"{environment}"* ]]; then
        has_prefix_placeholder=true
    fi

    resource_group="${resource_group//\{location\}/$SELECTED_LOCATION}"
    resource_group="${resource_group//\{prefix\}/$prefix}"
    resource_group="${resource_group//\{environment\}/$prefix}"

    if [ "$has_prefix_placeholder" = false ] && [ "${#DEPLOYMENT_PREFIXES[@]}" -gt 1 ]; then
        resource_group="$resource_group-$prefix"
    fi
    if [ "$has_location_placeholder" = false ]; then
        resource_group="$resource_group-$SELECTED_LOCATION"
    fi

    echo -e "\n${YELLOW}Final Configuration:${NC}"
    echo "  Prefix/Environment: $prefix"
    echo "  Selected Region: $SELECTED_LOCATION"
    echo "  Resource Group: $resource_group"

    echo -e "\n${CYAN}Ensuring resource group exists...${NC}"
    rg_exists="$(az group exists --name "$resource_group")"
    if [ "$rg_exists" = "false" ]; then
        echo -e "${GREEN}Creating resource group: $resource_group${NC}"
        az group create --name "$resource_group" --location "$SELECTED_LOCATION" >/dev/null
    else
        echo -e "${GREEN}Resource group already exists: $resource_group${NC}"
    fi

    data_lake_containers_json="$(echo "$CONFIG_JSON" | jq -c '.services.datalake.containers // ["data"]')"

    temp_params_file="$(mktemp)"

    echo "$CONFIG_JSON" | jq \
      --arg projectName "$PROJECT_NAME" \
      --arg location "$SELECTED_LOCATION" \
      --arg environment "$environment" \
      --argjson adminObjectIds "$ADMIN_OBJECT_IDS_JSON" \
      --argjson dataLakeContainers "$data_lake_containers_json" \
      '{
        "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
        contentVersion: "1.0.0.0",
        parameters: {
          projectName: { value: $projectName },
          location: { value: $location },
          environment: { value: $environment },
          adminObjectIds: { value: $adminObjectIds },

          enableVNet: { value: (.networking.enabled // true) },
          vnetAddressPrefix: { value: .networking.vnetAddressPrefix },
          containerAppsSubnetPrefix: { value: .networking.containerAppsSubnetPrefix },
          privateEndpointSubnetPrefix: { value: .networking.privateEndpointSubnetPrefix },
          sqlSubnetPrefix: { value: .networking.sqlSubnetPrefix },
          apimSubnetPrefix: { value: (.networking.apimSubnetPrefix // "10.0.4.0/27") },

          enableOpenAI: { value: (.services.openai.enabled // false) },
          openAIPrivateEndpointEnabled: { value: (.services.openai.privateEndpointEnabled // true) },
          enableCosmosDB: { value: (.services.cosmosdb.enabled // false) },
          cosmosPrivateEndpointEnabled: { value: (.services.cosmosdb.privateEndpointEnabled // true) },
          enableDataLake: { value: (.services.datalake.enabled // false) },
          dataLakePrivateEndpointEnabled: { value: (.services.datalake.privateEndpointEnabled // true) },
          enableSQLDB: { value: (.services.sqldb.enabled // false) },
          sqlPrivateEndpointEnabled: { value: (.services.sqldb.privateEndpointEnabled // true) },
          enableAISearch: { value: (.services.aisearch.enabled // false) },
          aiSearchPrivateEndpointEnabled: { value: (.services.aisearch.privateEndpointEnabled // true) },
          enableContainerApps: { value: (.services.containerApps.enabled // false) },
          enableContainerRegistry: { value: (.services.containerRegistry.enabled // false) },
          containerRegistryPrivateEndpointEnabled: { value: (.services.containerRegistry.privateEndpointEnabled // true) },
          enableKeyVault: { value: (.services.keyVault.enabled // false) },
          keyVaultPrivateEndpointEnabled: { value: (.services.keyVault.privateEndpointEnabled // true) },
          enableMonitoring: { value: (.services.monitoring.enabled // false) },
          enableAPIM: { value: (.services.apim.enabled // false) },
          enableFrontDoor: { value: (.services.frontDoor.enabled // false) },
          enableRedis: { value: (.services.redis.enabled // false) },
          redisPrivateEndpointEnabled: { value: (.services.redis.privateEndpointEnabled // true) },
          enablePolicy: { value: (.policy.enabled // false) },

          openAIDeployments: { value: (.services.openai.deployments // []) },
          openAIContentFilterPolicy: { value: (.services.openai.contentFilterPolicy // "default") },

          cosmosEnableNoSQL: { value: (.services.cosmosdb.enableNoSQL // true) },
          cosmosEnableGremlin: { value: (.services.cosmosdb.enableGremlin // true) },
          cosmosConsistencyLevel: { value: (.services.cosmosdb.consistencyLevel // "Session") },
          cosmosEnableServerless: { value: (.services.cosmosdb.enableServerless // false) },
          cosmosEnableAnalyticalStorage: { value: (.services.cosmosdb.enableAnalyticalStorage // false) },
          cosmosAdditionalRegions: { value: (.services.cosmosdb.additionalRegions // []) },

          sqlDatabaseSku: { value: (.services.sqldb.databaseSku // "S1") },
          sqlAdminUsername: { value: (.services.sqldb.adminUsername // "sqladmin") },
          sqlAllowedIpRules: { value: (.services.sqldb.allowedIpRules // []) },
          sqlZoneRedundant: { value: (.services.sqldb.zoneRedundant // false) },

          aiSearchSku: { value: (.services.aisearch.sku // "standard") },
          aiSearchReplicaCount: { value: (.services.aisearch.replicaCount // 1) },
          aiSearchPartitionCount: { value: (.services.aisearch.partitionCount // 1) },
          aiSearchSemanticTier: { value: (.services.aisearch.semanticSearchTier // "free") },

          containerAppsEnableDapr: { value: (.services.containerApps.enableDapr // false) },
          containerAppsZoneRedundant: { value: (.services.containerApps.zoneRedundant // false) },
          containerAppsCustomDomain: { value: (.services.containerApps.customDomain // {}) },

          containerRegistrySku: { value: (.services.containerRegistry.sku // "Premium") },
          containerRegistryGeoReplicationLocations: { value: (.services.containerRegistry.geoReplicationLocations // []) },

          dataLakeSku: { value: (.services.datalake.sku // "Standard_LRS") },
          dataLakeContainers: { value: $dataLakeContainers },

          keyVaultSku: { value: (.services.keyVault.sku // "standard") },
          keyVaultSoftDeleteRetentionDays: { value: (.services.keyVault.softDeleteRetentionInDays // 90) },

          logAnalyticsRetentionDays: { value: (.services.monitoring.retentionInDays // 30) },

          apimPublisherEmail: { value: (.services.apim.publisherEmail // "") },
          apimPublisherName: { value: (.services.apim.publisherName // "") },
          apimSku: { value: (.services.apim.sku // "Developer") },

          frontDoorEnableWaf: { value: (.services.frontDoor.enableWaf // false) },

          redisSku: { value: (.services.redis.sku // "Standard") },
          redisCapacity: { value: (.services.redis.capacity // 1) },

          requiredTags: { value: (.policy.requiredTags // ["reason", "purpose"]) },
          policyEnforcementMode: { value: (.policy.enforcementMode // "Default") },

          tags: { value: (.tags // {}) }
        }
      }' > "$temp_params_file"

    if [ "$WHAT_IF" = true ]; then
        echo -e "\n${MAGENTA}[WHAT-IF MODE][$prefix] Previewing deployment changes...${NC}"
        az deployment group what-if \
            --resource-group "$resource_group" \
            --template-file "$TEMP_TEMPLATE_FILE" \
            --parameters "@$temp_params_file"
    else
        deployment_name="ai-landing-zone-$prefix-$(date +%Y%m%d-%H%M%S)"

        az deployment group create \
            --name "$deployment_name" \
            --resource-group "$resource_group" \
            --template-file "$TEMP_TEMPLATE_FILE" \
            --parameters "@$temp_params_file" \
            --mode Incremental \
            --verbose

        echo -e "\n${GREEN}Deployment completed successfully for prefix '$prefix'!${NC}"
        echo -e "\n${CYAN}Retrieving deployment outputs for '$prefix'...${NC}"
        outputs="$(az deployment group show \
            --name "$deployment_name" \
            --resource-group "$resource_group" \
            --query properties.outputs \
            --output json)"

        echo -e "\n${YELLOW}Deployment Outputs ($prefix):${NC}"
        echo "$outputs" | jq -r 'to_entries[] | "  \(.key): \(.value.value)"'
    fi

    rm -f "$temp_params_file"
done

rm -f "$TEMP_TEMPLATE_FILE"

echo -e "\n${CYAN}Deployment script completed.${NC}"
