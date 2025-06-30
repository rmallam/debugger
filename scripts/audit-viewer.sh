#!/bin/bash

# audit-viewer.sh - View and analyze audit logs from the debugger solution
# Usage: ./audit-viewer.sh [options]

set -e

# Configuration
NAMESPACE="fttc-ancillary"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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
}

# Function to show recent audit logs
show_recent_logs() {
    local lines="${1:-50}"
    
    log "Showing last $lines audit log entries..."
    echo ""
    
    # Get logs from all daemon pods
    local pods=$(oc get pods -l app=debugger-daemon -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}')
    
    if [[ -z "$pods" ]]; then
        warn "No debugger daemon pods found"
        return
    fi
    
    # Collect logs from all pods and sort by timestamp
    local temp_file="/tmp/audit-logs-$$.txt"
    
    for pod in $pods; do
        local node=$(oc get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.nodeName}')
        oc logs "$pod" -n "$NAMESPACE" --tail="$lines" 2>/dev/null | grep "AUDIT" | sed "s/^/[$node] /" >> "$temp_file" 2>/dev/null || true
    done
    
    if [[ -s "$temp_file" ]]; then
        # Sort by timestamp and display
        sort "$temp_file" | tail -"$lines" | while IFS= read -r line; do
            if echo "$line" | grep -q "VIOLATION"; then
                echo -e "${RED}$line${NC}"
            elif echo "$line" | grep -q "EXECUTE"; then
                echo -e "${GREEN}$line${NC}"
            else
                echo -e "${CYAN}$line${NC}"
            fi
        done
    else
        warn "No audit logs found"
    fi
    
    rm -f "$temp_file"
}

# Function to show audit logs for a specific user
show_user_logs() {
    local user="$1"
    local lines="${2:-50}"
    
    log "Showing audit logs for user '$user' (last $lines entries)..."
    echo ""
    
    local pods=$(oc get pods -l app=debugger-daemon -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}')
    
    if [[ -z "$pods" ]]; then
        warn "No debugger daemon pods found"
        return
    fi
    
    local temp_file="/tmp/audit-logs-user-$$.txt"
    
    for pod in $pods; do
        local node=$(oc get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.nodeName}')
        oc logs "$pod" -n "$NAMESPACE" --tail=1000 2>/dev/null | grep "AUDIT" | grep "$user" | sed "s/^/[$node] /" >> "$temp_file" 2>/dev/null || true
    done
    
    if [[ -s "$temp_file" ]]; then
        sort "$temp_file" | tail -"$lines" | while IFS= read -r line; do
            if echo "$line" | grep -q "VIOLATION"; then
                echo -e "${RED}$line${NC}"
            elif echo "$line" | grep -q "EXECUTE"; then
                echo -e "${GREEN}$line${NC}"
            else
                echo -e "${CYAN}$line${NC}"
            fi
        done
    else
        warn "No audit logs found for user '$user'"
    fi
    
    rm -f "$temp_file"
}

# Function to show violations only
show_violations() {
    local lines="${1:-50}"
    
    log "Showing privilege violations (last $lines entries)..."
    echo ""
    
    local pods=$(oc get pods -l app=debugger-daemon -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}')
    
    if [[ -z "$pods" ]]; then
        warn "No debugger daemon pods found"
        return
    fi
    
    local temp_file="/tmp/audit-violations-$$.txt"
    
    for pod in $pods; do
        local node=$(oc get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.nodeName}')
        oc logs "$pod" -n "$NAMESPACE" --tail=1000 2>/dev/null | grep "VIOLATION" | sed "s/^/[$node] /" >> "$temp_file" 2>/dev/null || true
    done
    
    if [[ -s "$temp_file" ]]; then
        sort "$temp_file" | tail -"$lines" | while IFS= read -r line; do
            echo -e "${RED}$line${NC}"
        done
    else
        info "No privilege violations found"
    fi
    
    rm -f "$temp_file"
}

# Function to generate audit report
generate_report() {
    local hours="${1:-24}"
    local report_file="audit-report-$(date +%Y%m%d-%H%M%S).txt"
    
    log "Generating audit report for the last $hours hours..."
    
    local pods=$(oc get pods -l app=debugger-daemon -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}')
    
    if [[ -z "$pods" ]]; then
        warn "No debugger daemon pods found"
        return
    fi
    
    {
        echo "==============================================="
        echo "DEBUGGER AUDIT REPORT"
        echo "Generated: $(date)"
        echo "Period: Last $hours hours"
        echo "Namespace: $NAMESPACE"
        echo "==============================================="
        echo ""
        
        echo "SUMMARY:"
        echo "--------"
        
        local temp_file="/tmp/audit-full-$$.txt"
        
        for pod in $pods; do
            local node=$(oc get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.nodeName}')
            oc logs "$pod" -n "$NAMESPACE" --since="${hours}h" 2>/dev/null | grep "AUDIT" | sed "s/^/[$node] /" >> "$temp_file" 2>/dev/null || true
        done
        
        if [[ -s "$temp_file" ]]; then
            local total_events=$(wc -l < "$temp_file")
            local execute_events=$(grep -c "EXECUTE" "$temp_file" || echo "0")
            local violation_events=$(grep -c "VIOLATION" "$temp_file" || echo "0")
            local unique_users=$(grep -o '"user":"[^"]*"' "$temp_file" | sort -u | wc -l)
            local unique_nodes=$(grep -o '^\[[^]]*\]' "$temp_file" | sort -u | wc -l)
            
            echo "Total Events: $total_events"
            echo "Command Executions: $execute_events"
            echo "Privilege Violations: $violation_events"
            echo "Unique Users: $unique_users"
            echo "Nodes Accessed: $unique_nodes"
            echo ""
            
            if [[ $violation_events -gt 0 ]]; then
                echo "PRIVILEGE VIOLATIONS:"
                echo "--------------------"
                grep "VIOLATION" "$temp_file" | sort
                echo ""
            fi
            
            echo "COMMAND EXECUTIONS:"
            echo "------------------"
            grep "EXECUTE" "$temp_file" | sort
            echo ""
            
            echo "DETAILED LOG:"
            echo "------------"
            sort "$temp_file"
        else
            echo "No audit events found in the last $hours hours"
        fi
        
        rm -f "$temp_file"
        
    } > "$report_file"
    
    log "Report generated: $report_file"
    
    # Also display summary on screen
    echo ""
    info "=== REPORT SUMMARY ==="
    head -20 "$report_file" | tail -10
}

# Function to follow live audit logs
follow_logs() {
    log "Following live audit logs (press Ctrl+C to stop)..."
    echo ""
    
    local pods=$(oc get pods -l app=debugger-daemon -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}')
    
    if [[ -z "$pods" ]]; then
        warn "No debugger daemon pods found"
        return
    fi
    
    # Follow logs from all daemon pods
    for pod in $pods; do
        {
            local node=$(oc get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.nodeName}')
            oc logs -f "$pod" -n "$NAMESPACE" 2>/dev/null | grep --line-buffered "AUDIT" | while IFS= read -r line; do
                if echo "$line" | grep -q "VIOLATION"; then
                    echo -e "${RED}[$node] $line${NC}"
                elif echo "$line" | grep -q "EXECUTE"; then
                    echo -e "${GREEN}[$node] $line${NC}"
                else
                    echo -e "${CYAN}[$node] $line${NC}"
                fi
            done
        } &
    done
    
    # Wait for all background processes
    wait
}

# Function to show help
show_help() {
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  recent [N]          Show last N audit log entries (default: 50)"
    echo "  user <user> [N]     Show audit logs for specific user (last N entries)"
    echo "  violations [N]      Show privilege violations only (last N entries)"
    echo "  report [hours]      Generate detailed audit report for last N hours (default: 24)"
    echo "  follow              Follow live audit logs"
    echo "  help                Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 recent 100       # Show last 100 audit entries"
    echo "  $0 user john 20     # Show last 20 entries for user 'john'"
    echo "  $0 violations       # Show privilege violations"
    echo "  $0 report 48        # Generate 48-hour report"
    echo "  $0 follow           # Follow live logs"
}

# Main function
main() {
    check_prerequisites
    
    case "${1:-recent}" in
        recent)
            show_recent_logs "${2:-50}"
            ;;
        user)
            if [[ -z "$2" ]]; then
                error "User name required"
                echo "Usage: $0 user <username> [lines]"
                exit 1
            fi
            show_user_logs "$2" "${3:-50}"
            ;;
        violations)
            show_violations "${2:-50}"
            ;;
        report)
            generate_report "${2:-24}"
            ;;
        follow)
            follow_logs
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            error "Unknown command: $1"
            show_help
            exit 1
            ;;
    esac
}

# Run main function
main "$@"