#!/bin/bash

# execute-command.sh - Execute tcpdump or ncat commands on OpenShift worker nodes using Red Hat recommended approach
# Usage: ./execute-command.sh <node-name> <pod-name> <pod-namespace> <command> [arguments...]
# Usage for node-level debugging: ./execute-command.sh <node-name> - - <command> [arguments...]

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR="/tmp/debugger-$$"

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
    
    # Create temp directory
    mkdir -p "$TEMP_DIR"
    
    log "Prerequisites check passed"
}

# Function to validate command
validate_command() {
    local cmd="$1"
    
    if [[ "$cmd" != "tcpdump" && "$cmd" != "ncat" ]]; then
        error "Only 'tcpdump' and 'ncat' commands are allowed"
        echo "Usage: $0 <node-name> <pod-name> <pod-namespace> <command> [arguments...]"
        echo "Usage: $0 <node-name> - - <command> [arguments...]  # for node-level debugging"
        exit 1
    fi
}

# Function to validate tcpdump arguments
validate_tcpdump_args() {
    local args="$@"
    
    # Basic validation - prevent dangerous options
    if echo "$args" | grep -E "(>|>>|\||exec|system|&)" > /dev/null; then
        error "Dangerous tcpdump options detected"
        exit 1
    fi
    
    # Ensure output file is in safe location if -w is used
    if echo "$args" | grep -E "\-w" > /dev/null; then
        if ! echo "$args" | grep -E "\-w\s+/host/var/tmp/" > /dev/null; then
            error "tcpdump output files must be written to /host/var/tmp/ directory"
            exit 1
        fi
    fi
}

# Function to validate ncat arguments  
validate_ncat_args() {
    local args="$@"
    
    # Basic validation for ncat
    if echo "$args" | grep -E "(--exec|--sh-exec|-e|>|>>|\||&)" > /dev/null; then
        error "Dangerous ncat options detected"
        exit 1
    fi
}

# Function to get current user
get_current_user() {
    oc whoami 2>/dev/null || echo "unknown-user"
}

# Function to audit log
audit_log() {
    local action="$1"
    local node="$2"
    local pod="$3"
    local namespace="$4"
    local command="$5"
    local user=$(get_current_user)
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Create audit log entry
    local audit_entry="{\"timestamp\":\"$timestamp\",\"user\":\"$user\",\"node\":\"$node\",\"pod\":\"$pod\",\"namespace\":\"$namespace\",\"action\":\"$action\",\"command\":\"$command\"}"
    
    # Log to local file if possible
    echo "$audit_entry" >> "$TEMP_DIR/audit.log" 2>/dev/null || true
    
    # Also log to stdout
    echo "AUDIT: $timestamp - User: $user, Node: $node, Pod: $pod, Namespace: $namespace, Action: $action, Command: $command"
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

# Function to validate pod exists (if specified)
validate_pod() {
    local pod="$1"
    local namespace="$2"
    
    if [[ "$pod" != "-" && "$namespace" != "-" ]]; then
        if ! oc get pod "$pod" -n "$namespace" &> /dev/null; then
            error "Pod '$pod' does not exist in namespace '$namespace'"
            exit 1
        fi
    fi
}

# Function to create debug script for execution inside debug pod
create_debug_script() {
    local node_name="$1"
    local pod_name="$2"
    local namespace="$3"
    local command="$4"
    shift 4
    local args="$@"
    
    local script_file="$TEMP_DIR/debug-script.sh"
    
    cat > "$script_file" << 'EOF'
#!/bin/bash
set -e

NODE_NAME="$1"
POD_NAME="$2"
NAMESPACE="$3"
COMMAND="$4"
shift 4
ARGS="$@"

echo "=== OpenShift Network Debugger ==="
echo "Node: $NODE_NAME"
echo "Pod: $POD_NAME"
echo "Namespace: $NAMESPACE"
echo "Command: $COMMAND $ARGS"
echo "Time: $(date)"
echo "=================================="

# Function to setup nsenter parameters for OpenShift 4.9+
setup_nsenter_params() {
    local pod_name="$1"
    local namespace="$2"
    
    if [[ "$pod_name" == "-" || "$namespace" == "-" ]]; then
        echo "No specific pod target - using host network namespace"
        echo "nsenter_parameters=\"\""
        return 0
    fi
    
    echo "Setting up nsenter parameters for pod $pod_name in namespace $namespace..."
    
    # Get pod ID using crictl
    local pod_id=$(chroot /host crictl pods --namespace "${namespace}" --name "${pod_name}" -q 2>/dev/null || echo "")
    
    if [[ -z "$pod_id" ]]; then
        echo "ERROR: Could not find pod $pod_name in namespace $namespace on this node"
        return 1
    fi
    
    echo "Found pod ID: $pod_id"
    
    # Get network namespace path using crictl inspectp (for OpenShift 4.9+)
    local ns_path="/host$(chroot /host bash -c "crictl inspectp $pod_id | jq '.info.runtimeSpec.linux.namespaces[]|select(.type==\"network\").path' -r" 2>/dev/null || echo "")"
    
    if [[ -z "$ns_path" || "$ns_path" == "/host" ]]; then
        echo "ERROR: Could not determine network namespace path for pod $pod_name"
        return 1
    fi
    
    echo "Network namespace path: $ns_path"
    echo "nsenter_parameters=\"--net=${ns_path}\""
    return 0
}

# Setup nsenter parameters
nsenter_params_result=$(setup_nsenter_params "$POD_NAME" "$NAMESPACE")
if [[ $? -ne 0 ]]; then
    echo "$nsenter_params_result"
    exit 1
fi

# Extract nsenter parameters
eval "$nsenter_params_result"

# Show available interfaces
echo ""
echo "Available network interfaces:"
if [[ -n "$nsenter_parameters" ]]; then
    nsenter $nsenter_parameters -- chroot /host ip a 2>/dev/null || chroot /host ip a
else
    chroot /host ip a
fi

echo ""
echo "Available interfaces for tcpdump:"
if [[ -n "$nsenter_parameters" ]]; then
    nsenter $nsenter_parameters -- tcpdump -D 2>/dev/null || echo "tcpdump -D failed"
else
    tcpdump -D 2>/dev/null || echo "tcpdump -D failed"
fi

echo ""
echo "Executing command: $COMMAND $ARGS"
echo "=================================="

# Execute the command based on type
if [[ "$COMMAND" == "tcpdump" ]]; then
    # Ensure output directory exists
    mkdir -p /host/var/tmp
    
    # Add default output file if -w not specified
    if ! echo "$ARGS" | grep -q "\-w"; then
        OUTPUT_FILE="/host/var/tmp/${NODE_NAME}_$(date +%d_%m_%Y-%H_%M_%S-%Z).pcap"
        ARGS="-w $OUTPUT_FILE $ARGS"
        echo "Output will be saved to: $OUTPUT_FILE"
    fi
    
    # Execute tcpdump with nsenter if we have pod context
    if [[ -n "$nsenter_parameters" ]]; then
        echo "Running tcpdump in pod network namespace..."
        nsenter $nsenter_parameters -- tcpdump -nn $ARGS
    else
        echo "Running tcpdump in host network namespace..."
        tcpdump -nn $ARGS
    fi
    
elif [[ "$COMMAND" == "ncat" ]]; then
    # Execute ncat with nsenter if we have pod context
    if [[ -n "$nsenter_parameters" ]]; then
        echo "Running ncat in pod network namespace..."
        nsenter $nsenter_parameters -- ncat $ARGS
    else
        echo "Running ncat in host network namespace..."
        ncat $ARGS
    fi
else
    echo "ERROR: Unsupported command: $COMMAND"
    exit 1
fi

echo ""
echo "Command execution completed."

# List generated pcap files
if [[ "$COMMAND" == "tcpdump" ]]; then
    echo "Generated pcap files:"
    ls -la /host/var/tmp/*.pcap 2>/dev/null || echo "No pcap files found"
fi
EOF

    chmod +x "$script_file"
    echo "$script_file"
}

# Function to execute command using oc debug node
execute_debug_command() {
    local node_name="$1"
    local pod_name="$2"
    local namespace="$3"
    local command="$4"
    shift 4
    local args="$@"
    local user=$(get_current_user)
    
    log "Starting debug session on node '$node_name'"
    log "Target pod: $pod_name (namespace: $namespace)"
    log "Command: $command $args"
    log "User: $user"
    
    # Audit log the command execution attempt
    audit_log "EXECUTE" "$node_name" "$pod_name" "$namespace" "$command $args"
    
    # Create debug script
    local debug_script=$(create_debug_script "$node_name" "$pod_name" "$namespace" "$command" $args)
    
    log "Created debug script: $debug_script"
    
    # Execute using oc debug node
    log "Launching debug pod on node $node_name..."
    
    local debug_result=0
    
    # Use oc debug node with our script
    oc debug node/"$node_name" -- bash -c "
        # Copy our script to the debug pod
        cat > /tmp/debug-script.sh << 'SCRIPT_EOF'
$(cat "$debug_script")
SCRIPT_EOF
        chmod +x /tmp/debug-script.sh
        
        # Execute the script
        /tmp/debug-script.sh '$node_name' '$pod_name' '$namespace' '$command' $args
    " || debug_result=$?
    
    if [[ $debug_result -eq 0 ]]; then
        log "Debug command executed successfully"
        audit_log "SUCCESS" "$node_name" "$pod_name" "$namespace" "$command $args"
    else
        error "Debug command failed with exit code $debug_result"
        audit_log "FAILED" "$node_name" "$pod_name" "$namespace" "$command $args"
    fi
    
    return $debug_result
}

# Function to copy pcap files from debug pod
copy_pcap_files() {
    local node_name="$1"
    
    log "Checking for pcap files to copy from node $node_name..."
    
    # Get the debug pod name (it follows a pattern)
    local debug_pod=$(oc get pods --field-selector=spec.nodeName="$node_name" -l app=debug -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -z "$debug_pod" ]]; then
        warn "Could not find debug pod for node $node_name to copy files"
        return 1
    fi
    
    # Get debug pod namespace
    local debug_namespace=$(oc get pods --field-selector=spec.nodeName="$node_name" -l app=debug -o jsonpath='{.items[0].metadata.namespace}' 2>/dev/null || echo "")
    
    if [[ -z "$debug_namespace" ]]; then
        warn "Could not determine debug pod namespace"
        return 1
    fi
    
    log "Debug pod: $debug_pod in namespace $debug_namespace"
    
    # List available pcap files
    local pcap_files=$(oc exec -n "$debug_namespace" "$debug_pod" -- ls /host/var/tmp/*.pcap 2>/dev/null || echo "")
    
    if [[ -z "$pcap_files" ]]; then
        log "No pcap files found to copy"
        return 0
    fi
    
    log "Found pcap files to copy:"
    echo "$pcap_files"
    
    # Copy each pcap file
    for pcap_file in $pcap_files; do
        local filename=$(basename "$pcap_file")
        local local_file="$TEMP_DIR/$filename"
        
        log "Copying $pcap_file to $local_file"
        
        if oc cp -n "$debug_namespace" "$debug_pod":"$pcap_file" "$local_file"; then
            log "Successfully copied $filename"
            
            # Move to current directory
            mv "$local_file" "./$filename"
            log "pcap file available as: ./$filename"
        else
            error "Failed to copy $pcap_file"
        fi
    done
}

# Function to cleanup
cleanup() {
    log "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
}

# Main function
main() {
    if [[ $# -lt 4 ]]; then
        echo "Usage: $0 <node-name> <pod-name> <pod-namespace> <command> [arguments...]"
        echo "       $0 <node-name> - - <command> [arguments...]  # for node-level debugging"
        echo ""
        echo "Allowed commands: tcpdump, ncat"
        echo ""
        echo "Examples:"
        echo "  # Debug specific pod network"
        echo "  $0 worker-node-1 my-app-pod default tcpdump -i eth0 -c 100"
        echo "  $0 worker-node-1 my-app-pod default ncat -zv service-host 80"
        echo ""
        echo "  # Debug node-level network (host network namespace)"
        echo "  $0 worker-node-2 - - tcpdump -i eth0 -c 100"
        echo "  $0 worker-node-2 - - ncat -l 8080"
        echo ""
        echo "Note: This uses the Red Hat recommended approach with 'oc debug node'"
        exit 1
    fi
    
    local node_name="$1"
    local pod_name="$2"
    local namespace="$3"
    local command="$4"
    shift 4
    local args="$@"
    
    # Set up cleanup trap
    trap cleanup EXIT
    
    # Validate inputs
    check_prerequisites
    validate_node "$node_name"
    validate_pod "$pod_name" "$namespace"
    validate_command "$command"
    
    # Additional command-specific validation
    if [[ "$command" == "tcpdump" ]]; then
        validate_tcpdump_args $args
    elif [[ "$command" == "ncat" ]]; then
        validate_ncat_args $args
    fi
    
    log "=== OpenShift Network Debugger (Red Hat Solution) ==="
    log "Using Red Hat recommended approach for OpenShift 4.11+"
    log "Node: $node_name"
    log "Pod: $pod_name"
    log "Namespace: $namespace"
    log "Command: $command $args"
    log "======================================================"
    
    # Execute debug command
    if execute_debug_command "$node_name" "$pod_name" "$namespace" "$command" $args; then
        log "Debug session completed successfully"
        
        # Try to copy pcap files if this was a tcpdump command
        if [[ "$command" == "tcpdump" ]]; then
            copy_pcap_files "$node_name" || warn "Could not copy pcap files automatically"
        fi
        
        exit 0
    else
        error "Debug session failed"
        exit 1
    fi
}

# Run main function
main "$@"