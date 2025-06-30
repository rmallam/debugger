#!/bin/bash

# setup-github-secrets.sh - Helper script to set up GitHub secrets for OpenShift testing
# Usage: ./setup-github-secrets.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if oc command is available
    if ! command -v oc &> /dev/null; then
        error "OpenShift CLI 'oc' is not installed or not in PATH"
        echo "Please install oc CLI from: https://docs.openshift.com/container-platform/latest/cli_reference/openshift_cli/getting-started-cli.html"
        exit 1
    fi
    
    # Check if gh command is available
    if ! command -v gh &> /dev/null; then
        error "GitHub CLI 'gh' is not installed or not in PATH"
        echo "Please install gh CLI from: https://cli.github.com/"
        echo "Or manually set the secrets in your GitHub repository settings"
        exit 1
    fi
    
    # Check if logged into OpenShift
    if ! oc whoami &> /dev/null; then
        error "Not logged into OpenShift. Please run 'oc login' first"
        exit 1
    fi
    
    # Check if logged into GitHub
    if ! gh auth status &> /dev/null; then
        error "Not logged into GitHub. Please run 'gh auth login' first"
        exit 1
    fi
    
    log "Prerequisites check passed"
}

# Function to get OpenShift information
get_openshift_info() {
    log "Gathering OpenShift cluster information..."
    
    # Get API server URL
    OPENSHIFT_API=$(oc whoami --show-server)
    if [[ -z "$OPENSHIFT_API" ]]; then
        error "Could not determine OpenShift API server URL"
        exit 1
    fi
    
    info "OpenShift API Server: $OPENSHIFT_API"
    
    # Get current token
    CURRENT_TOKEN=$(oc whoami --show-token 2>/dev/null || echo "")
    if [[ -z "$CURRENT_TOKEN" ]]; then
        warn "Could not retrieve current token automatically"
        echo "You may need to create a service account token for long-term use"
    else
        info "Current token retrieved successfully"
    fi
    
    # Check current user permissions
    CURRENT_USER=$(oc whoami)
    info "Current user: $CURRENT_USER"
    
    if oc auth can-i debug nodes 2>/dev/null; then
        log "✓ Current user has cluster-admin permissions (full testing available)"
        CAN_DEBUG_NODES=true
    else
        warn "Current user does not have cluster-admin permissions"
        warn "Only namespace admin testing will be available"
        CAN_DEBUG_NODES=false
    fi
}

# Function to create service account for testing (recommended)
create_service_account() {
    log "Creating service account for GitHub Actions testing..."
    
    local sa_name="github-actions-debugger-test"
    local namespace="default"
    
    read -p "Enter namespace for service account (default: default): " input_namespace
    if [[ -n "$input_namespace" ]]; then
        namespace="$input_namespace"
    fi
    
    # Create service account
    oc create serviceaccount "$sa_name" -n "$namespace" 2>/dev/null || echo "Service account may already exist"
    
    # Create cluster role binding for full testing
    if [[ "$CAN_DEBUG_NODES" == "true" ]]; then
        echo "Do you want to grant cluster-admin permissions to the service account for full testing? (y/N)"
        read -r grant_admin
        if [[ "$grant_admin" =~ ^[Yy]$ ]]; then
            oc create clusterrolebinding "$sa_name-cluster-admin" \
                --clusterrole=cluster-admin \
                --serviceaccount="$namespace:$sa_name" 2>/dev/null || echo "ClusterRoleBinding may already exist"
            log "✓ Service account granted cluster-admin permissions"
        else
            oc create rolebinding "$sa_name-admin" \
                --clusterrole=admin \  
                --serviceaccount="$namespace:$sa_name" \
                -n "$namespace" 2>/dev/null || echo "RoleBinding may already exist"
            log "✓ Service account granted namespace admin permissions"
        fi
    fi
    
    # Get service account token
    log "Creating service account token..."
    SA_TOKEN=$(oc create token "$sa_name" -n "$namespace" --duration=8760h 2>/dev/null || echo "")
    
    if [[ -z "$SA_TOKEN" ]]; then
        # Try alternative method for older OpenShift versions
        local sa_secret=$(oc get serviceaccount "$sa_name" -n "$namespace" -o jsonpath='{.secrets[0].name}' 2>/dev/null || echo "")
        if [[ -n "$sa_secret" ]]; then
            SA_TOKEN=$(oc get secret "$sa_secret" -n "$namespace" -o jsonpath='{.data.token}' | base64 -d)
        fi
    fi
    
    if [[ -n "$SA_TOKEN" ]]; then
        log "✓ Service account token created successfully"
        OPENSHIFT_TOKEN="$SA_TOKEN"
        info "Using service account token for GitHub Actions"
    else
        error "Could not create service account token"
        exit 1
    fi
}

# Function to set GitHub secrets
set_github_secrets() {
    log "Setting GitHub repository secrets..."
    
    # Set OPENSHIFT_API secret
    if gh secret set OPENSHIFT_API --body "$OPENSHIFT_API"; then
        log "✓ OPENSHIFT_API secret set successfully"
    else
        error "Failed to set OPENSHIFT_API secret"
        exit 1
    fi
    
    # Set OPENSHIFT_TOKEN secret
    if gh secret set OPENSHIFT_TOKEN --body "$OPENSHIFT_TOKEN"; then
        log "✓ OPENSHIFT_TOKEN secret set successfully"
    else
        error "Failed to set OPENSHIFT_TOKEN secret"
        exit 1
    fi
    
    log "GitHub secrets configured successfully!"
}

# Function to verify setup
verify_setup() {
    log "Verifying setup..."
    
    # List current secrets (names only)
    echo "Current GitHub secrets:"
    gh secret list || echo "Could not list secrets"
    
    # Test OpenShift connection with the token
    log "Testing OpenShift connection..."
    if oc login --server="$OPENSHIFT_API" --token="$OPENSHIFT_TOKEN" &>/dev/null; then
        log "✓ OpenShift authentication successful with new token"
        echo "User: $(oc whoami)"
        echo "Server: $(oc whoami --show-server)"
    else
        error "OpenShift authentication failed with new token"
        exit 1
    fi
    
    log "Setup verification completed successfully!"
}

# Function to show next steps
show_next_steps() {
    echo ""
    log "=== Setup Complete ==="
    echo ""
    info "GitHub secrets have been configured for OpenShift testing:"
    echo "  - OPENSHIFT_API: $OPENSHIFT_API"
    echo "  - OPENSHIFT_TOKEN: *** (hidden)"
    echo ""
    info "Next steps:"
    echo "  1. Push code changes to trigger the workflow"
    echo "  2. Go to GitHub Actions tab to monitor test execution"  
    echo "  3. Review test reports in workflow artifacts"
    echo ""
    info "Manual workflow trigger:"
    echo "  1. Go to Actions > Test OpenShift Network Debugger Solution"
    echo "  2. Click 'Run workflow'"
    echo "  3. Select test level (basic/full/namespace-admin-only)"
    echo ""
    if [[ "$CAN_DEBUG_NODES" == "false" ]]; then
        warn "Note: Current setup will run namespace-admin testing only"
        warn "For full testing, grant cluster-admin permissions to the service account"
    fi
}

# Main function
main() {
    case "${1:-}" in
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Setup GitHub secrets for OpenShift Network Debugger testing."
            echo ""
            echo "Options:"
            echo "  -h, --help     Show this help message"
            echo ""
            echo "Prerequisites:"
            echo "  - oc CLI installed and logged into OpenShift"
            echo "  - gh CLI installed and authenticated to GitHub"
            echo "  - Repository owner/admin permissions on GitHub"
            echo ""
            echo "This script will:"
            echo "  1. Gather OpenShift cluster information"
            echo "  2. Create a service account for GitHub Actions (recommended)"
            echo "  3. Set GitHub repository secrets (OPENSHIFT_API, OPENSHIFT_TOKEN)"
            echo "  4. Verify the setup"
            exit 0
            ;;
        "")
            # Normal setup
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
    
    log "Setting up GitHub secrets for OpenShift Network Debugger testing..."
    echo ""
    
    check_prerequisites
    get_openshift_info
    
    echo ""
    echo "Choose token source:"
    echo "1. Use current user token (may expire)"
    echo "2. Create service account token (recommended for CI/CD)"
    read -p "Selection (1-2): " token_choice
    
    case "$token_choice" in
        1)
            if [[ -n "$CURRENT_TOKEN" ]]; then
                OPENSHIFT_TOKEN="$CURRENT_TOKEN"
                warn "Using current user token - this may expire"
            else
                error "Current user token not available"
                exit 1
            fi
            ;;
        2)
            create_service_account
            ;;
        *)
            error "Invalid selection"
            exit 1
            ;;
    esac
    
    set_github_secrets
    verify_setup
    show_next_steps
    
    log "GitHub secrets setup completed successfully!"
}

# Run main function
main "$@"