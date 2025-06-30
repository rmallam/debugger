#!/bin/bash

# test-solution.sh - Test the debugger solution functionality
# Usage: ./test-solution.sh [--verbose]

set -e

# Configuration
NAMESPACE="fttc-ancillary"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

VERBOSE=false
if [[ "$1" == "--verbose" ]]; then
    VERBOSE=true
fi

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

verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${BLUE}[DEBUG] $1${NC}"
    fi
}

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test result tracking
declare -a FAILED_TESTS=()

# Function to run a test
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    ((TESTS_TOTAL++))
    
    info "Running test: $test_name"
    
    if $test_function; then
        log "✓ PASSED: $test_name"
        ((TESTS_PASSED++))
    else
        error "✗ FAILED: $test_name"
        ((TESTS_FAILED++))
        FAILED_TESTS+=("$test_name")
    fi
    echo ""
}

# Function to check prerequisites
check_prerequisites() {
    verbose "Checking prerequisites..."
    
    # Check if oc command is available
    if ! command -v oc &> /dev/null; then
        error "OpenShift CLI 'oc' is not installed or not in PATH"
        return 1
    fi
    
    # Check if logged into OpenShift
    if ! oc whoami &> /dev/null; then
        error "Not logged into OpenShift. Please run 'oc login' first"
        return 1
    fi
    
    # Check if namespace exists
    if ! oc get namespace "$NAMESPACE" &> /dev/null; then
        error "Namespace '$NAMESPACE' does not exist"
        return 1
    fi
    
    verbose "Prerequisites check passed"
    return 0
}

# Test 1: Check if SCC exists and is properly configured
test_scc_configuration() {
    verbose "Testing SCC configuration..."
    
    # Check if SCC exists
    if ! oc get scc debugger-privileged-scc &> /dev/null; then
        error "SCC 'debugger-privileged-scc' not found"
        return 1
    fi
    
    # Check required capabilities
    local capabilities=$(oc get scc debugger-privileged-scc -o jsonpath='{.allowedCapabilities[*]}')
    for cap in NET_ADMIN NET_RAW SYS_ADMIN SYS_PTRACE; do
        if ! echo "$capabilities" | grep -q "$cap"; then
            error "Missing capability: $cap"
            return 1
        fi
    done
    
    # Check privileged container setting
    local privileged=$(oc get scc debugger-privileged-scc -o jsonpath='{.allowPrivilegedContainer}')
    if [[ "$privileged" != "true" ]]; then
        error "SCC does not allow privileged containers"
        return 1
    fi
    
    verbose "SCC configuration is correct"
    return 0
}

# Test 2: Check RBAC resources
test_rbac_configuration() {
    verbose "Testing RBAC configuration..."
    
    # Check service account
    if ! oc get sa debugger-sa -n "$NAMESPACE" &> /dev/null; then
        error "ServiceAccount 'debugger-sa' not found"
        return 1
    fi
    
    # Check role
    if ! oc get role debugger-role -n "$NAMESPACE" &> /dev/null; then
        error "Role 'debugger-role' not found"
        return 1
    fi
    
    # Check role binding
    if ! oc get rolebinding debugger-rolebinding -n "$NAMESPACE" &> /dev/null; then
        error "RoleBinding 'debugger-rolebinding' not found"
        return 1
    fi
    
    # Check cluster role
    if ! oc get clusterrole debugger-node-access &> /dev/null; then
        error "ClusterRole 'debugger-node-access' not found"
        return 1
    fi
    
    # Check cluster role binding
    if ! oc get clusterrolebinding debugger-node-access-binding &> /dev/null; then
        error "ClusterRoleBinding 'debugger-node-access-binding' not found"
        return 1
    fi
    
    verbose "RBAC configuration is correct"
    return 0
}

# Test 3: Check ConfigMap and scripts
test_configmap_scripts() {
    verbose "Testing ConfigMap and scripts..."
    
    # Check if ConfigMap exists
    if ! oc get configmap debugger-scripts -n "$NAMESPACE" &> /dev/null; then
        error "ConfigMap 'debugger-scripts' not found"
        return 1
    fi
    
    # Check if required scripts are present
    local scripts=$(oc get configmap debugger-scripts -n "$NAMESPACE" -o jsonpath='{.data}' | jq -r 'keys[]')
    for script in command-validator.sh entrypoint.sh; do
        if ! echo "$scripts" | grep -q "$script"; then
            error "Missing script: $script"
            return 1
        fi
    done
    
    verbose "ConfigMap and scripts are present"
    return 0
}

# Test 4: Check DaemonSet deployment
test_daemonset_deployment() {
    verbose "Testing DaemonSet deployment..."
    
    # Check if DaemonSet exists
    if ! oc get daemonset debugger-daemon -n "$NAMESPACE" &> /dev/null; then
        error "DaemonSet 'debugger-daemon' not found"
        return 1
    fi
    
    # Check DaemonSet status
    local desired=$(oc get daemonset debugger-daemon -n "$NAMESPACE" -o jsonpath='{.status.desiredNumberScheduled}')
    local ready=$(oc get daemonset debugger-daemon -n "$NAMESPACE" -o jsonpath='{.status.numberReady}')
    
    if [[ "$ready" -eq 0 ]]; then
        error "No DaemonSet pods are ready"
        return 1
    fi
    
    if [[ "$ready" -lt "$desired" ]]; then
        warn "Not all DaemonSet pods are ready ($ready/$desired)"
        # This is a warning, not a failure
    fi
    
    verbose "DaemonSet deployment is healthy ($ready/$desired pods ready)"
    return 0
}

# Test 5: Test basic command execution
test_basic_command_execution() {
    verbose "Testing basic command execution..."
    
    # Get first available worker node
    local node=$(oc get nodes -l node-role.kubernetes.io/worker='' -o jsonpath='{.items[0].metadata.name}')
    if [[ -z "$node" ]]; then
        error "No worker nodes found"
        return 1
    fi
    
    verbose "Testing on node: $node"
    
    # Test tcpdump command (should succeed)
    local temp_output="/tmp/test-output-$$.txt"
    if timeout 60 "$SCRIPT_DIR/execute-command.sh" "$node" tcpdump -i lo -c 5 > "$temp_output" 2>&1; then
        verbose "tcpdump command executed successfully"
        if [[ "$VERBOSE" == "true" ]]; then
            echo "Command output:"
            cat "$temp_output"
        fi
    else
        error "tcpdump command failed"
        cat "$temp_output" >&2
        rm -f "$temp_output"
        return 1
    fi
    
    rm -f "$temp_output"
    return 0
}

# Test 6: Test command validation (should fail)
test_command_validation() {
    verbose "Testing command validation..."
    
    # Get first available worker node
    local node=$(oc get nodes -l node-role.kubernetes.io/worker='' -o jsonpath='{.items[0].metadata.name}')
    if [[ -z "$node" ]]; then
        error "No worker nodes found"
        return 1
    fi
    
    # Test invalid command (should fail)
    local temp_output="/tmp/test-validation-$$.txt"
    if timeout 30 "$SCRIPT_DIR/execute-command.sh" "$node" ping -c 3 127.0.0.1 > "$temp_output" 2>&1; then
        error "Invalid command was allowed (should have been blocked)"
        cat "$temp_output" >&2
        rm -f "$temp_output"
        return 1
    else
        # Command should fail with specific error message
        if grep -q "not allowed" "$temp_output"; then
            verbose "Command validation working correctly"
        else
            error "Command failed but not due to validation"
            cat "$temp_output" >&2
            rm -f "$temp_output"
            return 1
        fi
    fi
    
    rm -f "$temp_output"
    return 0
}

# Test 7: Test audit logging
test_audit_logging() {
    verbose "Testing audit logging..."
    
    # Check if daemon pods are generating logs
    local pods=$(oc get pods -l app=debugger-daemon -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}')
    
    if [[ -z "$pods" ]]; then
        error "No daemon pods found"
        return 1
    fi
    
    local found_logs=false
    for pod in $pods; do
        if oc logs "$pod" -n "$NAMESPACE" --tail=50 | grep -q "Starting debugger daemon"; then
            found_logs=true
            break
        fi
    done
    
    if [[ "$found_logs" == "false" ]]; then
        error "No audit logs found in daemon pods"
        return 1
    fi
    
    verbose "Audit logging is working"
    return 0
}

# Test 8: Test job cleanup
test_job_cleanup() {
    verbose "Testing job cleanup mechanism..."
    
    # Check TTL configuration in job template
    if ! grep -q "ttlSecondsAfterFinished: 3600" "$SCRIPT_DIR/../k8s/job-template.yaml"; then
        error "Job template missing TTL configuration"
        return 1
    fi
    
    # Check for old jobs (should be cleaned up)
    local old_jobs=$(oc get jobs -n "$NAMESPACE" --field-selector status.successful=1 --no-headers | wc -l)
    
    verbose "Found $old_jobs completed jobs (will be cleaned up automatically)"
    return 0
}

# Test 9: Test resource limits
test_resource_limits() {
    verbose "Testing resource limits..."
    
    # Check DaemonSet resource limits
    local limits=$(oc get daemonset debugger-daemon -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].resources.limits}')
    
    if [[ -z "$limits" ]]; then
        warn "No resource limits set on DaemonSet"
        # This is a warning, not a failure for basic functionality
        return 0
    fi
    
    verbose "Resource limits are configured"
    return 0
}

# Test 10: Test monitoring setup (if available)
test_monitoring_setup() {
    verbose "Testing monitoring setup..."
    
    # Check if Prometheus monitoring is configured
    if oc get servicemonitor debugger-audit-monitor -n "$NAMESPACE" &> /dev/null; then
        verbose "ServiceMonitor found"
    else
        verbose "ServiceMonitor not found (monitoring not configured)"
    fi
    
    if oc get prometheusrule debugger-alerts -n "$NAMESPACE" &> /dev/null; then
        verbose "PrometheusRule found"
    else
        verbose "PrometheusRule not found (monitoring not configured)"
    fi
    
    # This test always passes as monitoring is optional
    return 0
}

# Function to run all tests
run_all_tests() {
    log "Starting debugger solution tests..."
    echo ""
    
    run_test "Prerequisites Check" check_prerequisites
    run_test "SCC Configuration" test_scc_configuration
    run_test "RBAC Configuration" test_rbac_configuration
    run_test "ConfigMap and Scripts" test_configmap_scripts
    run_test "DaemonSet Deployment" test_daemonset_deployment
    run_test "Basic Command Execution" test_basic_command_execution
    run_test "Command Validation" test_command_validation
    run_test "Audit Logging" test_audit_logging
    run_test "Job Cleanup Configuration" test_job_cleanup
    run_test "Resource Limits" test_resource_limits
    run_test "Monitoring Setup" test_monitoring_setup
}

# Function to show test summary
show_summary() {
    echo ""
    info "=== TEST SUMMARY ==="
    echo "Total Tests: $TESTS_TOTAL"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
    
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo ""
        error "Failed Tests:"
        for test in "${FAILED_TESTS[@]}"; do
            echo "  - $test"
        done
        echo ""
        error "Some tests failed. Please review the output above and fix the issues."
        return 1
    else
        echo ""
        log "All tests passed! The debugger solution is working correctly."
        return 0
    fi
}

# Function to show help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --verbose    Show detailed test output"
    echo "  --help       Show this help message"
    echo ""
    echo "This script tests the OpenShift network debugger solution functionality."
    echo "It verifies all components are properly installed and working."
}

# Main function
main() {
    case "${1:-}" in
        --help|-h)
            show_help
            exit 0
            ;;
        --verbose)
            VERBOSE=true
            ;;
        "")
            # Default behavior
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
    
    run_all_tests
    show_summary
}

# Run main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi