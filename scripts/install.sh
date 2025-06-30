#!/bin/bash

# install.sh - Setup for OpenShift Network Debugger using Red Hat solution approach
# Usage: ./install.sh

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
    log "Checking prerequisites for Red Hat solution approach..."
    
    # Check if oc command is available
    if ! command -v oc &> /dev/null; then
        error "OpenShift CLI 'oc' is not installed or not in PATH"
        exit 1
    fi
    
    # Check if logged into OpenShift
    if ! oc whoami &> /dev/null; then
        error "Not logged into OpenShift. Please run 'oc login' first"
        exit 1
    fi
    
    # Check if user has cluster-admin permissions
    if ! oc auth can-i debug nodes 2>/dev/null; then
        warn "You don't have cluster-admin permissions to debug nodes"
        warn "You may need to request cluster-admin access or use a service account with appropriate permissions"
        warn "The solution will still work but some functionality may be limited"
    else
        log "✓ Cluster-admin permissions confirmed"
    fi
    
    # Check OpenShift version
    local version=$(oc version -o json | jq -r '.openshiftVersion' 2>/dev/null || echo "unknown")
    if [[ "$version" != "unknown" ]]; then
        info "OpenShift version: $version"
        if [[ "$version" =~ ^4\.(11|12|13|14|15) ]]; then
            log "✓ OpenShift version $version is supported"
        else
            warn "OpenShift version $version may not be fully supported. Recommended: 4.11+"
        fi
    fi
    
    # Check if jq is available (needed for JSON parsing)
    if ! command -v jq &> /dev/null; then
        warn "jq is not installed. Some functionality may be limited"
        warn "Install jq for better JSON parsing capabilities"
    else
        log "✓ jq is available for JSON parsing"
    fi
    
    log "Prerequisites check completed"
}

# Function to verify execute script
verify_execute_script() {
    log "Verifying execute script..."
    
    local script_path="$SCRIPT_DIR/execute-command.sh"
    
    if [[ ! -f "$script_path" ]]; then
        error "Execute script not found: $script_path"
        exit 1
    fi
    
    if [[ ! -x "$script_path" ]]; then
        warn "Execute script is not executable, fixing..."
        chmod +x "$script_path"
    fi
    
    log "✓ Execute script is ready"
}

# Function to test basic functionality
test_basic_functionality() {
    log "Testing basic functionality..."
    
    # Get first available node
    local node=$(oc get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [[ -z "$node" ]]; then
        error "No nodes found or accessible"
        exit 1
    fi
    
    info "Testing with node: $node"
    
    # Test parameter validation (should fail)
    if "$SCRIPT_DIR/execute-command.sh" 2>/dev/null; then
        error "Script should require parameters"
        exit 1
    fi
    
    # Test invalid command validation (should fail)
    if "$SCRIPT_DIR/execute-command.sh" "$node" - - "invalid-command" 2>/dev/null; then
        error "Script should reject invalid commands"
        exit 1
    fi
    
    log "✓ Basic functionality test passed"
}

# Function to show usage information
show_usage_info() {
    log "Setup completed successfully!"
    echo ""
    info "=== OpenShift Network Debugger (Red Hat Solution) ==="
    echo ""
    echo "This solution uses the Red Hat recommended approach for network debugging"
    echo "in OpenShift 4.11+ using 'oc debug node' functionality."
    echo ""
    echo "Usage Examples:"
    echo ""
    echo "  # Debug specific pod network namespace:"
    echo "  ./scripts/execute-command.sh worker-node-1 my-app-pod default tcpdump -i eth0 -c 100"
    echo ""
    echo "  # Test connectivity from pod context:"
    echo "  ./scripts/execute-command.sh worker-node-1 client-pod default ncat -zv service-host 80"
    echo ""
    echo "  # Debug node-level network (host network):"
    echo "  ./scripts/execute-command.sh worker-node-2 - - tcpdump -i eth0 -c 100"
    echo ""
    echo "  # Save packet capture to file:"
    echo "  ./scripts/execute-command.sh worker-node-1 app-pod default tcpdump -i eth0 -w /host/var/tmp/debug.pcap -c 1000"
    echo ""
    echo "Key Features:"
    echo "  ✓ Uses Red Hat official approach (oc debug node)"
    echo "  ✓ Pod network namespace isolation"
    echo "  ✓ Command validation and audit logging"
    echo "  ✓ No persistent privileged containers"
    echo "  ✓ OpenShift 4.11+ optimized"
    echo ""
    echo "Next Steps:"
    echo "  1. Test the solution: ./scripts/test-solution.sh"
    echo "  2. Set up monitoring: ./scripts/setup-monitoring.sh"
    echo "  3. View audit logs: ./scripts/audit-viewer.sh"
    echo ""
}

# Function to uninstall the solution
uninstall_solution() {
    log "Uninstalling OpenShift Network Debugger solution..."
    
    # Get current namespace or use default
    local current_namespace=$(oc project -q 2>/dev/null || echo "fttc-ancillary")
    
    echo ""
    warn "This will remove the debugger solution from namespace: $current_namespace"
    warn "This action cannot be undone."
    echo ""
    read -p "Continue with uninstallation? [y/N]: " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        log "Uninstallation cancelled"
        exit 0
    fi
    
    echo ""
    log "Proceeding with uninstallation..."
    
    # Remove DaemonSet
    log "Removing DaemonSet..."
    oc delete daemonset debugger-daemon -n "$current_namespace" --ignore-not-found=true || warn "Failed to remove DaemonSet"
    
    # Remove ConfigMap
    log "Removing ConfigMap..."
    oc delete configmap debugger-scripts -n "$current_namespace" --ignore-not-found=true || warn "Failed to remove ConfigMap"
    
    # Remove namespace-scoped RBAC resources
    log "Removing namespace RBAC resources..."
    oc delete rolebinding debugger-rolebinding -n "$current_namespace" --ignore-not-found=true || warn "Failed to remove RoleBinding"
    oc delete role debugger-role -n "$current_namespace" --ignore-not-found=true || warn "Failed to remove Role"
    oc delete serviceaccount debugger-sa -n "$current_namespace" --ignore-not-found=true || warn "Failed to remove ServiceAccount"
    
    # Remove cluster-scoped resources (be careful here)
    log "Removing cluster-scoped resources..."
    oc delete clusterrolebinding debugger-node-access-binding --ignore-not-found=true || warn "Failed to remove ClusterRoleBinding"
    oc delete clusterrole debugger-node-access --ignore-not-found=true || warn "Failed to remove ClusterRole"
    oc delete scc debugger-privileged-scc --ignore-not-found=true || warn "Failed to remove SecurityContextConstraints"
    
    # Remove monitoring resources
    log "Removing monitoring resources..."
    oc delete configmap debugger-alert-config -n "$current_namespace" --ignore-not-found=true || true
    
    # Try to remove monitoring resources if they exist
    if [[ -d "../monitoring" ]]; then
        oc delete -f ../monitoring/ -n "$current_namespace" --ignore-not-found=true 2>/dev/null || true
    fi
    
    # Clean up any remaining jobs
    log "Cleaning up remaining jobs..."
    oc delete jobs -l app=debugger -n "$current_namespace" --ignore-not-found=true || true
    
    # Wait for pods to terminate
    log "Waiting for pods to terminate..."
    oc wait --for=delete pods -l app=debugger-daemon -n "$current_namespace" --timeout=60s 2>/dev/null || echo "Some pods may still be terminating"
    
    log "✓ Uninstallation completed successfully!"
    echo ""
    info "The OpenShift Network Debugger solution has been removed from namespace: $current_namespace"
    info "Audit logs may be preserved on the nodes for compliance purposes"
}

# Main function
main() {
    case "${1:-}" in
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Setup for OpenShift Network Debugger using Red Hat solution approach."
            echo ""
            echo "Options:"
            echo "  -h, --help       Show this help message"
            echo "  --uninstall      Uninstall the debugger solution"
            echo ""
            echo "This script performs basic setup and verification for the"
            echo "Red Hat recommended network debugging approach in OpenShift 4.11+."
            exit 0
            ;;
        --uninstall)
            uninstall_solution
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
    
    log "Setting up OpenShift Network Debugger (Red Hat Solution)..."
    echo ""
    
    check_prerequisites
    verify_execute_script
    test_basic_functionality
    show_usage_info
    
    log "Setup completed successfully!"
}

# Run main function
main "$@"