#!/bin/bash

# execute-command.sh - Execute tcpdump or ncat commands on OpenShift worker nodes
# Usage: ./execute-command.sh <node-name> <command> [arguments...]

set -e

# Configuration
NAMESPACE="fttc-ancillary"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$(dirname "$SCRIPT_DIR")/k8s"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
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
    
    # Check if namespace exists and is accessible
    if ! oc get namespace "$NAMESPACE" &> /dev/null; then
        error "Namespace '$NAMESPACE' does not exist or is not accessible"
        exit 1
    fi
    
    log "Prerequisites check passed"
}

# Function to validate command
validate_command() {
    local cmd="$1"
    
    if [[ "$cmd" != "tcpdump" && "$cmd" != "ncat" ]]; then
        error "Only 'tcpdump' and 'ncat' commands are allowed"
        echo "Usage: $0 <node-name> <tcpdump|ncat> [arguments...]"
        exit 1
    fi
}

# Function to get current user
get_current_user() {
    oc whoami 2>/dev/null || echo "unknown-user"
}

# Function to check if node exists
validate_node() {
    local node="$1"
    
    if ! oc get node "$node" &> /dev/null; then
        error "Node '$node' does not exist or is not accessible"
        echo "Available nodes:"
        oc get nodes -o name | sed 's/node\///'
        exit 1
    fi
}

# Function to generate job name
generate_job_name() {
    local timestamp=$(date +%s)
    local user=$(get_current_user | tr '[:upper:]' '[:lower:]' | tr '@' '-' | tr '.' '-')
    echo "debugger-job-${user}-${timestamp}"
}

# Function to create and run job
create_job() {
    local node_name="$1"
    local command="$2"
    shift 2
    local args="$@"
    local user=$(get_current_user)
    local job_name=$(generate_job_name)
    
    log "Creating job '$job_name' on node '$node_name'"
    log "Command: $command $args"
    log "User: $user"
    
    # Create temporary job file
    local temp_job="/tmp/${job_name}.yaml"
    
    # Replace placeholders in job template
    sed -e "s/TIMESTAMP/$(date +%s)/g" \
        -e "s/USER_PLACEHOLDER/${user}/g" \
        -e "s/NODE_PLACEHOLDER/${node_name}/g" \
        -e "s/COMMAND_PLACEHOLDER/${command} ${args}/g" \
        "$K8S_DIR/job-template.yaml" > "$temp_job"
    
    # Apply the job
    if oc apply -f "$temp_job"; then
        log "Job created successfully"
        
        # Wait for job to complete and show logs
        log "Waiting for job to complete..."
        
        # Wait for pod to be created
        local pod_name=""
        local max_wait=60
        local wait_count=0
        
        while [[ -z "$pod_name" && $wait_count -lt $max_wait ]]; do
            pod_name=$(oc get pods -l job-name="$job_name" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
            if [[ -z "$pod_name" ]]; then
                sleep 1
                ((wait_count++))
            fi
        done
        
        if [[ -z "$pod_name" ]]; then
            error "Timeout waiting for job pod to be created"
            cleanup_job "$job_name"
            exit 1
        fi
        
        log "Pod created: $pod_name"
        
        # Follow the logs
        log "Command output:"
        echo "----------------------------------------"
        
        # Wait for pod to start and then follow logs
        oc logs -f "$pod_name" 2>/dev/null || {
            warn "Could not follow logs, checking final status..."
            sleep 10
            oc logs "$pod_name" 2>/dev/null || error "Failed to get logs"
        }
        
        echo "----------------------------------------"
        
        # Check job status
        local job_status=$(oc get job "$job_name" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || echo "Unknown")
        
        if [[ "$job_status" == "True" ]]; then
            log "Job completed successfully"
        else
            local job_failed=$(oc get job "$job_name" -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null || echo "False")
            if [[ "$job_failed" == "True" ]]; then
                error "Job failed"
            else
                warn "Job status unknown"
            fi
        fi
        
        # Show audit information
        log "Audit trail:"
        oc logs -l app=debugger-daemon --tail=10 | grep "AUDIT.*$(get_current_user)" | tail -5 || warn "No recent audit logs found"
        
    else
        error "Failed to create job"
        exit 1
    fi
    
    # Cleanup
    rm -f "$temp_job"
}

# Function to cleanup job
cleanup_job() {
    local job_name="$1"
    log "Cleaning up job '$job_name'"
    oc delete job "$job_name" --ignore-not-found=true
}

# Main function
main() {
    if [[ $# -lt 2 ]]; then
        echo "Usage: $0 <node-name> <command> [arguments...]"
        echo ""
        echo "Allowed commands: tcpdump, ncat"
        echo ""
        echo "Examples:"
        echo "  $0 worker-node-1 tcpdump -i eth0 -c 100"
        echo "  $0 worker-node-2 ncat -l 8080"
        exit 1
    fi
    
    local node_name="$1"
    local command="$2"
    shift 2
    local args="$@"
    
    # Validate inputs
    check_prerequisites
    validate_node "$node_name"
    validate_command "$command"
    
    # Create and run job
    create_job "$node_name" "$command" $args
}

# Run main function
main "$@"