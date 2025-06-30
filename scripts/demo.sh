#!/bin/bash

# demo.sh - Demonstration script for the debugger solution
# Usage: ./demo.sh

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

# Demo functions
print_header() {
    echo -e "${BLUE}"
    echo "=========================================="
    echo "$1"
    echo "=========================================="
    echo -e "${NC}"
}

print_step() {
    echo -e "${GREEN}[DEMO] $1${NC}"
    sleep 2
}

print_command() {
    echo -e "${CYAN}$ $1${NC}"
    sleep 1
}

wait_for_user() {
    echo -e "${YELLOW}Press Enter to continue...${NC}"
    read -r
}

# Main demo function
main() {
    print_header "OpenShift Network Debugger Solution Demo"
    
    echo "This demo will show you how to:"
    echo "1. Install the debugger solution"
    echo "2. Execute network debugging commands"
    echo "3. View audit logs and security features"
    echo "4. Monitor and manage the solution"
    echo ""
    wait_for_user
    
    # Step 1: Installation
    print_header "1. Installation"
    print_step "Installing the debugger solution..."
    print_command "./scripts/install.sh"
    echo "This command will install:"
    echo "- Security Context Constraints (SCC)"
    echo "- RBAC roles and bindings"
    echo "- DaemonSet for privileged container access"
    echo "- ConfigMap with command validation scripts"
    echo ""
    wait_for_user
    
    # Step 2: Setup Monitoring
    print_header "2. Monitoring Setup"
    print_step "Setting up monitoring and alerting..."
    print_command "./scripts/setup-monitoring.sh"
    echo "This configures:"
    echo "- Prometheus rules for alerting"
    echo "- Audit log collection"
    echo "- Security violation alerts"
    echo ""
    wait_for_user
    
    # Step 3: Test Installation
    print_header "3. Testing Installation"
    print_step "Running comprehensive tests..."
    print_command "./scripts/test-solution.sh"
    echo "This verifies:"
    echo "- All components are properly installed"
    echo "- Security configurations are correct"
    echo "- Command execution works as expected"
    echo "- Audit logging is functional"
    echo ""
    wait_for_user
    
    # Step 4: Command Execution Examples
    print_header "4. Command Execution Examples"
    
    print_step "Getting available worker nodes..."
    print_command "oc get nodes -l node-role.kubernetes.io/worker=''"
    echo ""
    
    print_step "Example 1: Network packet capture with tcpdump"
    print_command "./scripts/execute-command.sh worker-node-1 tcpdump -i eth0 -c 100"
    echo "This command:"
    echo "- Captures 100 packets on eth0 interface"
    echo "- Runs on the specified worker node"
    echo "- Is logged for audit purposes"
    echo ""
    wait_for_user
    
    print_step "Example 2: Network connectivity test with ncat"
    print_command "./scripts/execute-command.sh worker-node-1 ncat -zv service-host 80"
    echo "This command:"
    echo "- Tests TCP connectivity to service-host on port 80"
    echo "- Uses zero-I/O mode for port scanning"
    echo "- Provides verbose output"
    echo ""
    wait_for_user
    
    print_step "Example 3: HTTP traffic analysis"
    print_command "./scripts/execute-command.sh worker-node-1 tcpdump -i eth0 -c 50 port 80"
    echo "This command:"
    echo "- Captures HTTP traffic specifically"
    echo "- Limits capture to 50 packets"
    echo "- Useful for web service debugging"
    echo ""
    wait_for_user
    
    # Step 5: Security Features
    print_header "5. Security Features Demonstration"
    
    print_step "Example: Blocked command (security violation)"
    print_command "./scripts/execute-command.sh worker-node-1 ping -c 3 127.0.0.1"
    echo "This command will FAIL because:"
    echo "- Only tcpdump and ncat are allowed"
    echo "- The violation will be logged and alerted"
    echo "- Security team will be notified"
    echo ""
    wait_for_user
    
    print_step "Example: Dangerous option blocking"
    print_command "./scripts/execute-command.sh worker-node-1 tcpdump -i eth0 -w /tmp/capture.pcap"
    echo "This command will FAIL because:"
    echo "- File writing is blocked for security"
    echo "- Command injection prevention"
    echo "- Audit trail maintained"
    echo ""
    wait_for_user
    
    # Step 6: Audit and Monitoring
    print_header "6. Audit and Monitoring"
    
    print_step "Viewing recent audit logs"
    print_command "./scripts/audit-viewer.sh recent 20"
    echo "This shows:"
    echo "- Recent command executions"
    echo "- User identity and timestamps"
    echo "- Success/failure status"
    echo ""
    wait_for_user
    
    print_step "Checking for security violations"
    print_command "./scripts/audit-viewer.sh violations"
    echo "This displays:"
    echo "- Unauthorized command attempts"
    echo "- Blocked operations"
    echo "- Security incidents"
    echo ""
    wait_for_user
    
    print_step "Generating audit report"
    print_command "./scripts/audit-viewer.sh report 24"
    echo "This creates:"
    echo "- Comprehensive 24-hour activity report"
    echo "- Summary statistics"
    echo "- Detailed command log"
    echo ""
    wait_for_user
    
    print_step "Live audit monitoring"
    print_command "./scripts/audit-viewer.sh follow"
    echo "This provides:"
    echo "- Real-time audit log streaming"
    echo "- Immediate violation alerts"
    echo "- Color-coded output for easy reading"
    echo ""
    wait_for_user
    
    # Step 7: User-Specific Logs
    print_header "7. User Activity Tracking"
    
    print_step "Viewing specific user activity"
    print_command "./scripts/audit-viewer.sh user \$(oc whoami) 10"
    echo "This shows:"
    echo "- Commands executed by specific user"
    echo "- Individual accountability"
    echo "- Compliance reporting"
    echo ""
    wait_for_user
    
    # Step 8: Administrative Tasks
    print_header "8. Administrative Tasks"
    
    print_step "Checking system health"
    print_command "oc get all -l app=debugger-daemon -n $NAMESPACE"
    echo ""
    
    print_step "Monitoring DaemonSet status"
    print_command "oc get ds debugger-daemon -n $NAMESPACE"
    echo ""
    
    print_step "Viewing daemon pod logs"
    print_command "oc logs -l app=debugger-daemon -n $NAMESPACE --tail=20"
    echo ""
    wait_for_user
    
    # Step 9: Configuration and Customization
    print_header "9. Configuration and Customization"
    
    echo "The solution can be easily customized:"
    echo ""
    echo "📝 Add new commands:"
    echo "   Edit 'command-validator.sh' in the ConfigMap"
    echo ""
    echo "🔐 Modify RBAC permissions:"
    echo "   Update 'k8s/rbac.yaml'"
    echo ""
    echo "📊 Add custom alerts:"
    echo "   Edit 'monitoring/prometheus-rules.yaml'"
    echo ""
    echo "🔔 Configure notifications:"
    echo "   Set environment variables for email/Slack"
    echo ""
    wait_for_user
    
    # Step 10: Cleanup and Uninstall
    print_header "10. Cleanup and Uninstall"
    
    print_step "To uninstall the solution:"
    print_command "./scripts/install.sh --uninstall"
    echo ""
    echo "This removes:"
    echo "- All deployed resources"
    echo "- Security configurations"
    echo "- Monitoring components"
    echo "- Preserves audit logs for compliance"
    echo ""
    wait_for_user
    
    # Final Summary
    print_header "Demo Complete!"
    
    echo -e "${GREEN}Summary of what we covered:${NC}"
    echo "✅ Secure installation with OpenShift native resources"
    echo "✅ Command validation and security controls"
    echo "✅ Comprehensive audit logging and monitoring"
    echo "✅ Real-time security violation alerts"
    echo "✅ Easy customization and extension"
    echo "✅ Administrative tools and maintenance"
    echo ""
    echo -e "${BLUE}Key Benefits:${NC}"
    echo "🔒 Controlled privileged access to worker nodes"
    echo "📝 Complete audit trail for compliance"
    echo "🚨 Real-time security monitoring and alerts"
    echo "🛠️ Shell-based for easy extension by bash users"
    echo "🏗️ Uses only OpenShift resources (no external dependencies)"
    echo ""
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "1. Review the documentation in the 'docs/' directory"
    echo "2. Customize the solution for your specific needs"
    echo "3. Train your team on the user guide"
    echo "4. Set up monitoring and alerting integration"
    echo "5. Establish regular audit review processes"
    echo ""
    echo -e "${CYAN}Thank you for exploring the OpenShift Network Debugger Solution!${NC}"
}

# Run the demo
main "$@"