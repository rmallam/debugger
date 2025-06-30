# OpenShift Network Debugger Solution

A secure solution for running network debugging tools (`tcpdump` and `ncat`) on OpenShift worker nodes with controlled access, comprehensive audit logging, and privilege violation alerts.

## 🎯 Overview

This solution enables application teams with limited OpenShift access to run specific network debugging commands on worker nodes while maintaining strict security controls. It uses OpenShift-native resources and shell scripts for easy deployment and extension.

## ✨ Key Features

- **🔒 Secure by Design**: Uses OpenShift SCC and RBAC for controlled privileged access
- **📝 Complete Audit Trail**: Logs all command executions with user, timestamp, and node details
- **🚨 Real-time Alerts**: Immediate notifications for privilege violations and unauthorized access
- **🎛️ Command Validation**: Only allows `tcpdump` and `ncat` with safety parameter enforcement
- **🔧 Shell-based**: Easy to extend and customize using familiar bash scripts
- **📊 Monitoring Ready**: Prometheus integration with pre-configured alerting rules
- **🏗️ OpenShift Native**: Uses only OpenShift resources (no external dependencies)

## 🚀 Quick Start

### Prerequisites
- OpenShift cluster with admin access
- OpenShift CLI (`oc`) installed
- Access to the `fttc-ancillary` namespace

### Installation
```bash
# Clone the repository
git clone <repository-url>
cd debugger

# Install the solution (requires cluster-admin privileges)
./scripts/install.sh

# Setup monitoring and alerting
./scripts/setup-monitoring.sh

# Test the installation
./scripts/test-solution.sh
```

### Basic Usage
```bash
# Execute tcpdump on a worker node
./scripts/execute-command.sh worker-node-1 tcpdump -i eth0 -c 100

# Test network connectivity with ncat
./scripts/execute-command.sh worker-node-2 ncat -zv service-host 80

# View audit logs
./scripts/audit-viewer.sh recent 50

# Check for security violations
./scripts/audit-viewer.sh violations
```

## 📁 Repository Structure

```
debugger/
├── k8s/                          # OpenShift resource definitions
│   ├── scc.yaml                  # Security Context Constraints
│   ├── rbac.yaml                 # Role-Based Access Control
│   ├── configmap.yaml            # Command validation scripts
│   ├── daemonset.yaml            # Privileged container deployment
│   └── job-template.yaml         # Job template for command execution
├── scripts/                      # Management scripts
│   ├── install.sh                # Main installation script
│   ├── execute-command.sh        # Command execution interface
│   ├── audit-viewer.sh           # Audit log viewer and analyzer
│   ├── setup-monitoring.sh       # Monitoring and alerting setup
│   └── test-solution.sh          # Comprehensive test suite
├── monitoring/                   # Monitoring configurations
│   ├── prometheus-rules.yaml     # Prometheus alerting rules
│   └── logging-config.yaml       # Audit logging configuration
├── docs/                         # Documentation
│   ├── README.md                 # Detailed solution documentation
│   ├── USER_GUIDE.md             # User guide for application teams
│   └── ADMIN_GUIDE.md            # Administrator guide
└── README.md                     # This file
```

## 🛡️ Security Features

### Command Validation
- **Allowed Commands**: Only `tcpdump` and `ncat`
- **Blocked Operations**: File writes, command execution, pipe operations
- **Safety Parameters**: Automatic limits for packet capture counts

### Access Control
- **RBAC Integration**: Proper OpenShift role-based access control
- **Service Account Isolation**: Dedicated service account with minimal privileges
- **Namespace Scoping**: Restricted to specific namespace operations

### Audit and Monitoring
- **Comprehensive Logging**: All executions logged with full context
- **Real-time Alerts**: Immediate notifications for violations
- **Prometheus Integration**: Metrics and alerting rules included
- **Multiple Alert Channels**: Email, Slack, and syslog support

## 📖 Documentation

- **[Complete Documentation](docs/README.md)**: Detailed architecture and configuration
- **[User Guide](docs/USER_GUIDE.md)**: How to use the debugging tools
- **[Administrator Guide](docs/ADMIN_GUIDE.md)**: Installation, configuration, and maintenance

## 🔧 Common Use Cases

### Network Troubleshooting
```bash
# Capture HTTP traffic
./scripts/execute-command.sh worker-1 tcpdump -i eth0 -c 50 port 80

# Check service connectivity
./scripts/execute-command.sh worker-1 ncat -zv database-server 5432

# Monitor DNS queries
./scripts/execute-command.sh worker-1 tcpdump -i eth0 -c 20 port 53
```

### Service Debugging
```bash
# Test load balancer connectivity
./scripts/execute-command.sh worker-1 ncat -zv load-balancer 443

# Capture traffic to specific service
./scripts/execute-command.sh worker-1 tcpdump -i eth0 -c 100 host service-ip

# Check port accessibility
./scripts/execute-command.sh worker-1 ncat -z service-host 8080-8090
```

## 📊 Monitoring and Alerting

### Built-in Alerts
- **Privilege Violations**: Critical alerts for unauthorized commands
- **Daemon Health**: Warnings for pod failures
- **High Failure Rates**: Warnings for excessive job failures
- **Unauthorized Access**: Warnings for blocked commands

### Audit Analysis
```bash
# View recent activity
./scripts/audit-viewer.sh recent 100

# Check specific user activity
./scripts/audit-viewer.sh user developer@example.com

# Generate compliance reports
./scripts/audit-viewer.sh report 168  # Weekly report

# Monitor live activity
./scripts/audit-viewer.sh follow
```

## 🧪 Testing

The solution includes comprehensive tests:

```bash
# Run all tests
./scripts/test-solution.sh

# Run tests with detailed output
./scripts/test-solution.sh --verbose
```

Tests verify:
- ✅ Security Context Constraints configuration
- ✅ RBAC permissions and bindings
- ✅ DaemonSet deployment and health
- ✅ Command execution functionality
- ✅ Command validation and blocking
- ✅ Audit logging capabilities
- ✅ Resource limits and cleanup
- ✅ Monitoring integration

## 🔄 Maintenance

### Regular Tasks
```bash
# Check system health
./scripts/test-solution.sh

# Review audit logs
./scripts/audit-viewer.sh violations

# Update monitoring
./scripts/setup-monitoring.sh --status

# Backup configuration
oc get all,configmap,secret,sa,role,rolebinding -n fttc-ancillary -o yaml > backup.yaml
```

### Troubleshooting
```bash
# Check DaemonSet status
oc get ds debugger-daemon -n fttc-ancillary

# View pod logs
oc logs -l app=debugger-daemon -n fttc-ancillary

# Check job status
oc get jobs -n fttc-ancillary

# Verify permissions
oc auth can-i create jobs -n fttc-ancillary
```

## 🤝 Contributing

This solution is designed to be easily extensible:

1. **Adding Commands**: Edit the `command-validator.sh` script in the ConfigMap
2. **Custom Validation**: Enhance validation logic for new tools
3. **Additional Alerts**: Add rules to `monitoring/prometheus-rules.yaml`
4. **Extended RBAC**: Modify role definitions as needed

## 📄 License

This solution is provided as-is for OpenShift environments. Review and adapt according to your organization's security policies.

## 🆘 Support

1. Check the [troubleshooting documentation](docs/ADMIN_GUIDE.md#troubleshooting)
2. Review audit logs for security violations
3. Run the test suite to verify functionality
4. Contact your platform team for cluster-level issues

---

**Security Note**: This solution provides privileged access to worker nodes. Ensure proper review and approval processes are in place before deployment. All activities are logged and monitored for security compliance.