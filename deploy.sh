#!/usr/bin/env bash
set -Eeuo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
fail() { echo -e "${RED}❌ $*${NC}" >&2; exit 1; }
info() { echo -e "${YELLOW}ℹ️  $*${NC}"; }
ok() { echo -e "${GREEN}✅ $*${NC}"; }

# Configuration
PROJECT="aiagent"
ENVIRONMENT="dev"
LOCATION="eastus"
TIMESTAMP=$(date +%Y%m%d%H%M%S)
SUFFIX=$(openssl rand -hex 3 | tr -d '0123456789' | cut -c1-6)

# Resource names
RESOURCE_GROUP="rg-${PROJECT}-${ENVIRONMENT}-${SUFFIX}"
KEY_VAULT="kv-${PROJECT}${SUFFIX}"
AI_SERVICE="ai-${PROJECT}${SUFFIX}"

# Main execution
main() {
    info "Starting deployment..."
    
    # Login check
    if ! az account show >/dev/null 2>&1; then
        fail "Not logged into Azure. Run 'az login' first."
    fi
    
    # Get subscription info
    SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    ok "Using subscription: $SUBSCRIPTION_ID"
    
    # Create Resource Group
    info "Creating Resource Group: $RESOURCE_GROUP"
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags Project="$PROJECT" Environment="$ENVIRONMENT" \
        --output none || fail "Failed to create resource group"
    ok "Resource Group created: $RESOURCE_GROUP"
    
    # Create Key Vault
    info "Creating Key Vault: $KEY_VAULT"
    az keyvault create \
        --name "$KEY_VAULT" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --enable-rbac-authorization false \
        --sku standard \
        --tags Project="$PROJECT" Environment="$ENVIRONMENT" \
        --output none || fail "Failed to create Key Vault"
    ok "Key Vault created: $KEY_VAULT"
    
    # Create AI Service (Azure OpenAI)
    info "Creating Azure OpenAI Service: $AI_SERVICE"
    az cognitiveservices account create \
        --name "$AI_SERVICE" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --kind "OpenAI" \
        --sku "S0" \
        --yes \
        --tags Project="$PROJECT" Environment="$ENVIRONMENT" \
        --output none || {
            info "OpenAI creation failed, trying simpler AI service..."
            # Fallback to simpler cognitive service
            az cognitiveservices account create \
                --name "$AI_SERVICE" \
                --resource-group "$RESOURCE_GROUP" \
                --location "$LOCATION" \
                --kind "TextAnalytics" \
                --sku "F0" \
                --yes \
                --tags Project="$PROJECT" Environment="$ENVIRONMENT" \
                --output none || fail "Failed to create AI service"
        }
    ok "AI Service created: $AI_SERVICE"
    
    # Get AI service keys
    info "Retrieving AI service keys..."
    PRIMARY_KEY=$(az cognitiveservices account keys list \
        --name "$AI_SERVICE" \
        --resource-group "$RESOURCE_GROUP" \
        --query key1 -o tsv)
    
    ENDPOINT=$(az cognitiveservices account show \
        --name "$AI_SERVICE" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.endpoint -o tsv)
    
    # Store secrets in Key Vault
    info "Storing secrets in Key Vault..."
    az keyvault secret set \
        --vault-name "$KEY_VAULT" \
        --name "AiServiceKey" \
        --value "$PRIMARY_KEY" \
        --output none || fail "Failed to store AI key"
    
    az keyvault secret set \
        --vault-name "$KEY_VAULT" \
        --name "AiServiceEndpoint" \
        --value "$ENDPOINT" \
        --output none || fail "Failed to store AI endpoint"
    
    ok "Secrets stored in Key Vault"
    
    # Display summary
    echo ""
    echo "=========================================="
    echo "           DEPLOYMENT COMPLETE"
    echo "=========================================="
    echo "Resource Group:     $RESOURCE_GROUP"
    echo "Key Vault:          $KEY_VAULT"
    echo "AI Service:         $AI_SERVICE"
    echo "AI Endpoint:        $ENDPOINT"
    echo "Secrets stored in:  $KEY_VAULT"
    echo "  - AiServiceKey"
    echo "  - AiServiceEndpoint"
    echo "=========================================="
    echo ""
    
    ok "Deployment completed successfully!"
}

# Run main function
main "$@"