#!/bin/bash

# install.sh - Install the debugger solution on OpenShift
# Usage: ./install.sh

set -e

# Configuration
NAMESPACE="fttc-ancillary"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$(dirname "$SCRIPT_DIR")/k8s"

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
        exit 1
    fi
    
    # Check if logged into OpenShift
    if ! oc whoami &> /dev/null; then
        error "Not logged into OpenShift. Please run 'oc login' first"
        exit 1
    fi
    
    # Check if user has admin privileges
    local user=$(oc whoami)
    log "Current user: $user"
    
    # Check if user can create cluster-scoped resources
    if ! oc auth can-i create securitycontextconstraints &> /dev/null; then
        error "Current user does not have sufficient privileges to create SecurityContextConstraints"
        error "This installation requires cluster-admin privileges"
        exit 1
    fi
    
    log "Prerequisites check passed"
}

# Function to create namespace if it doesn't exist
create_namespace() {
    log "Checking namespace '$NAMESPACE'..."
    
    if ! oc get namespace "$NAMESPACE" &> /dev/null; then
        log "Creating namespace '$NAMESPACE'..."
        oc create namespace "$NAMESPACE"
    else
        log "Namespace '$NAMESPACE' already exists"
    fi
}

# Function to install SecurityContextConstraints
install_scc() {
    log "Installing SecurityContextConstraints..."
    
    if oc get scc debugger-privileged-scc &> /dev/null; then
        warn "SCC 'debugger-privileged-scc' already exists, updating..."
        oc apply -f "$K8S_DIR/scc.yaml"
    else
        log "Creating new SCC 'debugger-privileged-scc'..."
        oc apply -f "$K8S_DIR/scc.yaml"
    fi
    
    # Verify SCC was created
    if oc get scc debugger-privileged-scc &> /dev/null; then
        log "SCC installed successfully"
    else
        error "Failed to install SCC"
        exit 1
    fi
}

# Function to install RBAC resources
install_rbac() {
    log "Installing RBAC resources..."
    
    oc apply -f "$K8S_DIR/rbac.yaml" -n "$NAMESPACE"
    
    # Verify service account was created
    if oc get sa debugger-sa -n "$NAMESPACE" &> /dev/null; then
        log "RBAC resources installed successfully"
    else
        error "Failed to install RBAC resources"
        exit 1
    fi
}

# Function to install ConfigMap
install_configmap() {
    log "Installing ConfigMap with scripts..."
    
    oc apply -f "$K8S_DIR/configmap.yaml" -n "$NAMESPACE"
    
    # Verify ConfigMap was created
    if oc get configmap debugger-scripts -n "$NAMESPACE" &> /dev/null; then
        log "ConfigMap installed successfully"
    else
        error "Failed to install ConfigMap"
        exit 1
    fi
}

# Function to install DaemonSet
install_daemonset() {
    log "Installing DaemonSet..."
    
    oc apply -f "$K8S_DIR/daemonset.yaml" -n "$NAMESPACE"
    
    # Wait for DaemonSet to be ready
    log "Waiting for DaemonSet to be ready..."
    local max_wait=180
    local wait_count=0
    
    while [[ $wait_count -lt $max_wait ]]; do
        local ready_pods=$(oc get ds debugger-daemon -n "$NAMESPACE" -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")
        local desired_pods=$(oc get ds debugger-daemon -n "$NAMESPACE" -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "0")
        
        if [[ "$ready_pods" -gt 0 && "$ready_pods" == "$desired_pods" ]]; then
            log "DaemonSet is ready: $ready_pods/$desired_pods pods running"
            break
        fi
        
        info "Waiting for DaemonSet... ($ready_pods/$desired_pods pods ready)"
        sleep 5
        ((wait_count+=5))
    done
    
    if [[ $wait_count -ge $max_wait ]]; then
        warn "DaemonSet deployment may not be complete after ${max_wait}s"
        warn "You can check status with: oc get ds debugger-daemon -n $NAMESPACE"
    fi
}

# Function to verify installation
verify_installation() {
    log "Verifying installation..."
    
    echo ""
    info "=== Installation Summary ==="
    
    # Check SCC
    if oc get scc debugger-privileged-scc &> /dev/null; then
        echo "✓ SecurityContextConstraints: debugger-privileged-scc"
    else
        echo "✗ SecurityContextConstraints: NOT FOUND"
    fi
    
    # Check namespace
    if oc get namespace "$NAMESPACE" &> /dev/null; then
        echo "✓ Namespace: $NAMESPACE"
    else
        echo "✗ Namespace: NOT FOUND"
    fi
    
    # Check service account
    if oc get sa debugger-sa -n "$NAMESPACE" &> /dev/null; then
        echo "✓ ServiceAccount: debugger-sa"
    else
        echo "✗ ServiceAccount: NOT FOUND"
    fi
    
    # Check ConfigMap
    if oc get configmap debugger-scripts -n "$NAMESPACE" &> /dev/null; then
        echo "✓ ConfigMap: debugger-scripts"
    else
        echo "✗ ConfigMap: NOT FOUND"
    fi
    
    # Check DaemonSet
    local ready_pods=$(oc get ds debugger-daemon -n "$NAMESPACE" -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")
    local desired_pods=$(oc get ds debugger-daemon -n "$NAMESPACE" -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "0")
    
    if [[ "$ready_pods" -gt 0 ]]; then
        echo "✓ DaemonSet: debugger-daemon ($ready_pods/$desired_pods pods)"
    else
        echo "✗ DaemonSet: NOT READY"
    fi
    
    echo ""
    info "=== Next Steps ==="
    echo "1. Test the installation:"
    echo "   ./scripts/execute-command.sh <node-name> tcpdump -i eth0 -c 10"
    echo ""
    echo "2. View audit logs:"
    echo "   oc logs -l app=debugger-daemon -n $NAMESPACE | grep AUDIT"
    echo ""
    echo "3. Check available nodes:"
    echo "   oc get nodes"
    echo ""
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  --uninstall    Uninstall the debugger solution"
    echo ""
    echo "This script installs the OpenShift network debugger solution."
    echo "It requires cluster-admin privileges to create SecurityContextConstraints."
}

# Function to uninstall
uninstall() {
    log "Uninstalling debugger solution..."
    
    # Delete DaemonSet
    oc delete -f "$K8S_DIR/daemonset.yaml" -n "$NAMESPACE" --ignore-not-found=true
    
    # Delete ConfigMap
    oc delete -f "$K8S_DIR/configmap.yaml" -n "$NAMESPACE" --ignore-not-found=true
    
    # Delete RBAC
    oc delete -f "$K8S_DIR/rbac.yaml" -n "$NAMESPACE" --ignore-not-found=true
    
    # Delete SCC
    oc delete -f "$K8S_DIR/scc.yaml" --ignore-not-found=true
    
    # Note: We don't delete the namespace as it might contain other resources
    
    log "Uninstallation completed"
}

# Main function
main() {
    case "${1:-}" in
        -h|--help)
            show_usage
            exit 0
            ;;
        --uninstall)
            uninstall
            exit 0
            ;;
        "")
            # Normal installation
            ;;
        *)
            error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
    
    log "Starting debugger solution installation..."
    
    check_prerequisites
    create_namespace
    install_scc
    install_rbac
    install_configmap
    install_daemonset
    verify_installation
    
    log "Installation completed successfully!"
}

# Run main function
main "$@"