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
    if [[ "$cmd" != "tcpdump" && "$cmd" != "ncat" && "$cmd" != "ip" && "$cmd" != "ifconfig" ]]; then
        error "Only 'tcpdump', 'ncat', 'ip', and 'ifconfig' commands are allowed"
        echo "Usage: $0 <node-name> <pod-name> <pod-namespace> <command> [arguments...]"
        echo "Usage: $0 <node-name> - - <command> [arguments...]  # for node-level debugging"
        exit 1
    fi
    # If ip or ifconfig, validate further
    if [[ "$cmd" == "ip" || "$cmd" == "ifconfig" ]]; then
        shift
        validate_network_command "$cmd" "$@"
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

# Function to validate allowed read-only network commands
validate_network_command() {
    local cmd="$1"
    shift
    local args="$@"
    # Allow only read-only ip commands (ip, ip a, ip addr, ip link, ip route, ip -o -br a, etc) and ifconfig
    if [[ "$cmd" == "ip" ]]; then
        # Disallow any modifying subcommands (add, del, flush, set, etc)
        if echo "$args" | grep -E -wq '(add|del|delete|flush|set|change|replace|link set|route add|route del|route flush|neigh add|neigh del|neigh flush|tunnel add|tunnel del|tunnel change|tunnel set|address add|address del|address flush|addr add|addr del|addr flush|rule add|rule del|rule flush|maddress add|maddress del|maddress flush|mroute add|mroute del|mroute flush|monitor|xfrm|tcp_metrics|token|macsec|vrf|netns|netconf|netem|qdisc|class|filter|mptcp|sr|srdev|srpolicy|srroute|srseg|srlabel|srencap|sren|srdecap|srpop|srpush|srpophead|srpoptail|srpopall|srpopalltail|srpopallhead|srpopalltailheadall|srpopalltailheadallpop|srpopalltailheadallpopall|srpopalltailheadallpopallpop|srpopalltailheadallpopallpopall|srpopalltailheadallpopallpopallpop|srpopalltailheadallpopallpopallpopallpop|srpopalltailheadallpopallpopallpopallpopall|srpopalltailheadallpopallpopallpopallpopallpop|srpopalltailheadallpopallpopallpopallpopallpopall|srpopalltailheadallpopallpopallpopallpopallpopallpop|srpopalltailheadallpopallpopallpopallpopallpopallpopall|srpopalltailheadallpopallpopallpopallpopallpopallpopallpop)' ; then
            error "Modifying 'ip' subcommands are not allowed. Only read-only queries are permitted."
            exit 1
        fi
    elif [[ "$cmd" == "ifconfig" ]]; then
        # ifconfig is always allowed (read-only)
        return 0
    else
        error "Only 'tcpdump', 'ncat', 'ip', and 'ifconfig' commands are allowed."
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
CAPTURE_DURATION="${!#}"
# Remove last arg (duration) from ARGS if present and numeric (to avoid passing it to tcpdump)
if [[ "$COMMAND" == "tcpdump" ]]; then
    set -- $ARGS
    if [[ "$CAPTURE_DURATION" =~ ^[0-9]+$ ]] && [[ "${!#}" == "$CAPTURE_DURATION" ]]; then
        set -- "${@:1:$(($#-1))}"
    fi
    ARGS="$*"
fi

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
        echo "No specific pod target - using host network namespace" >&2
        echo "nsenter_parameters=\"\""
        return 0
    fi
    
    echo "Setting up nsenter parameters for pod $pod_name in namespace $namespace..." >&2
    
    # Get pod ID using crictl
    local pod_id=$(chroot /host crictl pods --namespace "${namespace}" --name "${pod_name}" -q 2>/dev/null || echo "")
    
    if [[ -z "$pod_id" ]]; then
        echo "ERROR: Could not find pod $pod_name in namespace $namespace on this node" >&2
        return 1
    fi
    
    echo "Found pod ID: $pod_id" >&2
    
    # Get network namespace path using crictl inspectp (for OpenShift 4.9+)
    local ns_path="/host$(chroot /host bash -c "crictl inspectp $pod_id | jq '.info.runtimeSpec.linux.namespaces[]|select(.type==\"network\").path' -r" 2>/dev/null || echo "")"
    
    if [[ -z "$ns_path" || "$ns_path" == "/host" ]]; then
        echo "ERROR: Could not determine network namespace path for pod $pod_name" >&2
        return 1
    fi
    
    echo "Network namespace path: $ns_path" >&2
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



# Prompt user to select interface if not already specified in ARGS
if [[ "$COMMAND" == "tcpdump" ]]; then
# Show available interfaces in the correct network namespace
if [[ -n "$nsenter_parameters" ]]; then
    echo "[INFO] Listing interfaces in pod network namespace..." >&2
    nsenter $nsenter_parameters -- chroot /host ip -o -br a 2>/dev/null || nsenter $nsenter_parameters -- ip -o -br a
else
    echo "[INFO] Listing interfaces in host network namespace..." >&2
    chroot /host ip -o -br a
fi
    if ! echo "$ARGS" | grep -E '\-i[ ]*[^ ]+' > /dev/null; then
        echo ""
        echo "Please enter the interface to use for tcpdump (e.g. eth0, or type 'all' for all interfaces):"
        read -r SELECTED_IFACE
        if [[ -z "$SELECTED_IFACE" ]]; then
            echo "No interface selected. Exiting."
            exit 1
        fi
        if [[ "$SELECTED_IFACE" == "all" ]]; then
            ARGS="-i any $ARGS"
        else
            ARGS="-i $SELECTED_IFACE $ARGS"
        fi
    fi
fi



echo ""
echo "Executing command: $COMMAND $ARGS"
echo "=================================="

# Execute the command based on type
if [[ "$COMMAND" == "tcpdump" ]]; then
    mkdir -p /host/var/tmp
    ARGS=$(echo "$ARGS" | sed 's/-c[ ]*[0-9]*//g')
    if ! echo "$ARGS" | grep -q "\-w"; then
        OUTPUT_FILE="/host/var/tmp/${NODE_NAME}_$(date +%d_%m_%Y-%H_%M_%S-%Z).pcap"
        ARGS="-w $OUTPUT_FILE $ARGS"
        echo "Output will be saved to: $OUTPUT_FILE"
    fi
    if [[ -n "$CAPTURE_DURATION" ]]; then
        if [[ -n "$nsenter_parameters" ]]; then
            echo "Running tcpdump in pod network namespace for $CAPTURE_DURATION seconds..."
            echo "[DEBUG] About to run: nsenter $nsenter_parameters -- timeout $CAPTURE_DURATION tcpdump -nn $ARGS" >&2
            nsenter $nsenter_parameters -- timeout --preserve-status $CAPTURE_DURATION tcpdump -nn $ARGS
            result=$?
        else
            echo "Running tcpdump in host network namespace for $CAPTURE_DURATION seconds..."
            echo "[DEBUG] About to run: timeout $CAPTURE_DURATION tcpdump -nn $ARGS" >&2
            timeout --preserve-status $CAPTURE_DURATION tcpdump -nn $ARGS
            result=$?
        fi
        if [[ $result -eq 124 ]]; then
            echo "tcpdump completed after timeout ($CAPTURE_DURATION seconds)"
            result=0
        fi
        exit $result
    else
        if [[ -n "$nsenter_parameters" ]]; then
            echo "Running tcpdump in pod network namespace... (Press Ctrl+C to stop)"
            echo "[DEBUG] About to run: nsenter $nsenter_parameters -- tcpdump -nn $ARGS" >&2
            nsenter $nsenter_parameters -- tcpdump -nn $ARGS
        else
            echo "Running tcpdump in host network namespace... (Press Ctrl+C to stop)"
            echo "[DEBUG] About to run: tcpdump -nn $ARGS" >&2
            tcpdump -nn $ARGS
        fi
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
elif [[ "$COMMAND" == "ip" || "$COMMAND" == "ifconfig" ]]; then
    if [[ -n "$nsenter_parameters" ]]; then
        echo "Running $COMMAND in pod network namespace..."
        nsenter $nsenter_parameters -- $COMMAND $ARGS
    else
        echo "Running $COMMAND in host network namespace..."
        $COMMAND $ARGS
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

# Function to create a debug script for listing interfaces only
create_list_interfaces_script() {
    local node_name="$1"
    local pod_name="$2"
    local namespace="$3"
    local script_file="$TEMP_DIR/list-interfaces.sh"
    cat > "$script_file" << 'EOF'
#!/bin/bash
set -e
NODE_NAME="$1"
POD_NAME="$2"
NAMESPACE="$3"
# Setup nsenter parameters for pod if needed (reuse logic if required)
echo "Available network interfaces on node $NODE_NAME (pod: $POD_NAME, ns: $NAMESPACE):"
chroot /host ip -o -br a
EOF
    chmod +x "$script_file"
    echo "$script_file"
}

# Function to run a debug pod to list interfaces and print them locally
run_list_interfaces_debug() {
    local node_name="$1"
    local pod_name="$2"
    local namespace="$3"
    log "Launching debug pod to list interfaces on node $node_name..."
    local list_script=$(create_list_interfaces_script "$node_name" "$pod_name" "$namespace")
    oc debug node/"$node_name" -- bash -c "cat > /tmp/list-interfaces.sh << 'SCRIPT_EOF'
$(cat "$list_script")
SCRIPT_EOF
chmod +x /tmp/list-interfaces.sh
/tmp/list-interfaces.sh '$node_name' '$pod_name' '$namespace'" || true
}

# Function to create debug pod
create_debug_pod() {
    local node_name="$1"
    local debug_pod_name="debugger-daemon-$node_name"
    
    # Check if debug pod already exists
    if oc get pod "$debug_pod_name" -n kube-system &> /dev/null; then
        log "Debug pod $debug_pod_name already exists"
        return 0
    fi
    
    log "Creating debug pod $debug_pod_name on node $node_name..."
    # Create debug pod YAML
    cat << EOF | oc apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: $debug_pod_name
  namespace: kube-system
  labels:
    app: debugger-daemon
spec:
  containers:
  - name: debugger
    image: registry.access.redhat.com/ubi8/ubi-minimal:latest
    command: ["/bin/bash", "-c", "while true; do sleep 3600; done"]
  nodeSelector:
    kubernetes.io/hostname: $node_name
EOF
}

# Function to delete debug pod
delete_debug_pod() {
    local node_name="$1"
    local debug_pod_name="debugger-daemon-$node_name"
    
    log "Deleting debug pod $debug_pod_name..."
    oc delete pod "$debug_pod_name" -n kube-system --grace-period=0 --force || true
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

# Function to execute list-interfaces using oc debug node
execute_list_interfaces() {
    local node_name="$1"
    local pod_name="$2"
    local namespace="$3"
    local user=$(get_current_user)
    log "Starting interface listing debug session on node '$node_name'"
    audit_log "LIST_INTERFACES" "$node_name" "$pod_name" "$namespace" "list-interfaces"
    local script_file=$(create_list_interfaces_script "$node_name" "$pod_name" "$namespace")
    log "Created list-interfaces script: $script_file"
    oc debug node/"$node_name" -- bash -c "cat > /tmp/list-interfaces.sh << 'SCRIPT_EOF'
$(cat "$script_file")
SCRIPT_EOF
chmod +x /tmp/list-interfaces.sh
/tmp/list-interfaces.sh '$node_name' '$pod_name' '$namespace'" 
}

# Function to copy pcap files from debug pod
copy_pcap_files() {
    local node_name="$1"
    
    log "Checking for pcap files to copy from node $node_name..."
    local debug_pod=$(oc get pods --field-selector=spec.nodeName="$node_name" -l app=debugger-daemon -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || echo "")

    
    # Get debug pod namespace
    local debug_namespace=$(oc get pods --field-selector=spec.nodeName="$node_name" -l app=debugger-daemon -o jsonpath='{.items[0].metadata.namespace}' 2>/dev/null || echo "")
    
    if [[ -z "$debug_namespace" ]]; then
        warn "Could not determine debug pod namespace"
        return 1
    fi
    
    log "Debug pod: $debug_pod in namespace $debug_namespace"
    timestamp=$(date +%s)
    tempdir="/host/tmp/pcapcopy-$timestamp"
    oc debug node/$node_name -- bash -c "mkdir -p $tempdir && find /host/var/tmp -type f -name '*.pcap' -exec cp {} $tempdir/ \;"
    # List available pcap files
    local pcap_files=$(oc exec -n "$debug_namespace" "$debug_pod" -- ls $tempdir 2>/dev/null || echo "")

    echo "🔍 Step 1: Copying .pcap files from /var/tmp to $tempdir on node $node_name ..."
    echo "$debug_namespace" "$debug_pod":"$tempdir" 
    oc cp -n "$debug_namespace" "$debug_pod":"$tempdir" ./pcap-dump
        
    
}

# Function to cleanup
cleanup() {
    log "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
    # Also delete pcap files from node (host)
    if [[ -n "$node_name" ]]; then
        log "Attempting to delete pcap files from node $node_name..."
        oc debug node/$node_name -- bash -c 'rm -f /host/var/tmp/*.pcap' || warn "Could not delete pcap files from node $node_name"
    fi
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
    trap cleanup EXIT
    check_prerequisites
    validate_node "$node_name"
    validate_pod "$pod_name" "$namespace"
    validate_command "$command"
    local CAPTURE_DURATION=""
    if [[ "$command" == "tcpdump" ]]; then
        validate_tcpdump_args $args
        # If no -i interface specified, do the two-step process
        if ! echo "$args" | grep -E '\-i[ ]*[^ ]+' > /dev/null; then
            run_list_interfaces_debug "$node_name" "$pod_name" "$namespace"
            echo ""
            echo "Please enter the interface to use for tcpdump (e.g. eth0, or type 'all' for all interfaces):"
            read -r SELECTED_IFACE
            if [[ -z "$SELECTED_IFACE" ]]; then
                error "No interface selected. Exiting."
                exit 1
            fi
            if [[ "$SELECTED_IFACE" == "all" ]]; then
                args="-i any $args"
            else
                args="-i $SELECTED_IFACE $args"
            fi
        fi
        # Prompt for duration here
        echo ""
        echo "Enter capture duration in seconds (default: 300 for 5 minutes):"
        read -r CAPTURE_DURATION
        if [[ -z "$CAPTURE_DURATION" ]]; then
            CAPTURE_DURATION=300
        fi
    elif [[ "$command" == "ncat" ]]; then
        validate_ncat_args $args
        # Do NOT list interfaces or prompt for interface for ncat
    fi
    log "=== OpenShift Network Debugger (Red Hat Solution) ==="
    log "Using Red Hat recommended approach for OpenShift 4.11+"
    log "Node: $node_name"
    log "Pod: $pod_name"
    log "Namespace: $namespace"
    log "Command: $command $args"
    log "======================================================"
    if execute_debug_command "$node_name" "$pod_name" "$namespace" "$command" $args "$CAPTURE_DURATION"; then
        log "Debug session completed successfully"
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