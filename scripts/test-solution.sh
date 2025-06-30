#!/bin/bash

# test-solution.sh - Test the debugger solution functionality using Red Hat approach
# Usage: ./test-solution.sh [--verbose]

# Note: Not using 'set -e' globally to allow proper test failure handling

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR="/tmp/debugger-test-$$"

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
    
    # Check cluster version for compatibility
    local version=$(oc version -o json | jq -r '.openshiftVersion' 2>/dev/null || echo "unknown")
    if [[ "$version" != "unknown" ]]; then
        info "OpenShift version: $version"
        if [[ ! "$version" =~ ^4\.(11|12|13|14|15) ]]; then
            warn "This solution is optimized for OpenShift 4.11+. Current version: $version"
        fi
    fi
    
    # Create temp directory
    mkdir -p "$TEMP_DIR"
    
    verbose "Prerequisites check passed"
    return 0
}

# Test 1: Check if we can create debug pods on nodes
test_debug_node_access() {
    verbose "Testing debug node access..."
    
    # Get first available node
    local node=$(oc get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [[ -z "$node" ]]; then
        error "No nodes found or accessible"
        return 1
    fi
    
    verbose "Testing debug access to node: $node"
    
    # Test basic debug node access
    local debug_result=0
    timeout 30 oc debug node/"$node" -- echo "Debug node access test" &>/dev/null || debug_result=$?
    
    if [[ $debug_result -eq 0 ]]; then
        verbose "Debug node access successful"
        return 0
    else
        error "Cannot create debug pod on node $node (may require cluster-admin)"
        return 1
    fi
}

# Test 2: Check script execution and validation
test_script_functionality() {
    verbose "Testing script functionality..."
    
    local script_path="$SCRIPT_DIR/execute-command.sh"
    
    # Check if script exists and is executable
    if [[ ! -x "$script_path" ]]; then
        error "Execute script not found or not executable: $script_path"
        return 1
    fi
    
    # Test script parameter validation (should fail with insufficient args)
    if "$script_path" 2>/dev/null; then
        error "Script should fail with insufficient arguments"
        return 1
    fi
    
    # Test invalid command validation
    local node=$(oc get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "test-node")
    if "$script_path" "$node" - - "invalid-command" 2>/dev/null; then
        error "Script should reject invalid commands"
        return 1
    fi
    
    verbose "Script validation working correctly"
    return 0
# Test 3: Test command validation logic (removed duplicate)

# Test 4: Test actual debug functionality (if cluster-admin)
test_debug_functionality() {
    verbose "Testing actual debug functionality..."
    
    local node=$(oc get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [[ -z "$node" ]]; then
        error "No nodes available for testing"
        return 1
    fi
    
    verbose "Testing debug functionality on node: $node"
    
    # Check if we have cluster-admin access (required for oc debug node)
    if ! oc auth can-i debug nodes 2>/dev/null; then
        warn "No cluster-admin access - skipping actual debug test"
        info "To test debug functionality, run with cluster-admin privileges"
        return 0  # Skip, don't fail
    fi
    
    # Test basic oc debug node functionality
    local test_output="$TEMP_DIR/debug_test.txt"
    if timeout 30 oc debug node/"$node" -- echo "Debug test successful" > "$test_output" 2>&1; then
        verbose "Debug node access working"
        if [[ "$VERBOSE" == "true" ]]; then
            echo "Debug output:"
            cat "$test_output" 2>/dev/null || echo "No output captured"
        fi
        return 0
    else
        error "Debug node access failed"
        if [[ "$VERBOSE" == "true" ]]; then
            echo "Debug error output:"
            cat "$test_output" 2>/dev/null || echo "No error output captured"
        fi
        return 1
    fi
}

# Test 5: Test audit logging functionality
# Test 5: Test audit logging functionality (removed duplicate)

cleanup_test() {
    verbose "Cleaning up test files..."
    rm -rf "$TEMP_DIR"
}
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

# Function to run all tests
run_all_tests() {
    log "Starting OpenShift Network Debugger tests (Red Hat solution approach)..."
    echo ""
    
    run_test "Prerequisites Check" check_prerequisites
    run_test "Debug Node Access" test_debug_node_access  
    run_test "Script Functionality" test_script_functionality
    run_test "Command Validation" test_command_validation
    run_test "Debug Functionality" test_debug_functionality
    run_test "Audit Logging" test_audit_logging
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
        log "All tests passed! The Red Hat solution-based debugger is working correctly."
        return 0
    fi
}

# Function to show help
show_help() {
    echo "Usage: $0 [--verbose] [--help]"
    echo ""
    echo "Test the OpenShift Network Debugger solution using Red Hat recommended approach."
    echo ""
    echo "Options:"
    echo "  --verbose    Show detailed test output"
    echo "  --help       Show this help message"
    echo ""
    echo "Requirements:"
    echo "  - OpenShift 4.11+ cluster"
    echo "  - oc CLI logged in"
    echo "  - cluster-admin access (for debug node functionality)"
    echo ""
    echo "This test suite validates:"
    echo "  - Prerequisites and environment setup"
    echo "  - Debug node access using 'oc debug node'"
    echo "  - Script functionality and validation"
    echo "  - Command validation logic"
    echo "  - Actual debug functionality (if cluster-admin)"
    echo "  - Audit logging capabilities"
}

# Main function
main() {
    # Set up cleanup trap
    trap 'cleanup_test 2>/dev/null || true' EXIT
    
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
    
    if show_summary; then
        exit 0
    else
        exit 1
    fi
}

# Run main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi