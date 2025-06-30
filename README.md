# OpenShift Network Debugger Solution

A secure solution for running network debugging tools (`tcpdump` and `ncat`) on OpenShift worker nodes using the Red Hat recommended approach for OpenShift 4.11+. This implementation provides controlled access, comprehensive audit logging, and follows OpenShift best practices.

## 🎯 Overview

This solution enables application teams to run specific network debugging commands on worker nodes while maintaining strict security controls. It implements the official Red Hat solution for packet capture using `oc debug node` with proper network namespace isolation.

## ✨ Key Features

- **🔒 Red Hat Recommended**: Uses the official Red Hat solution approach for OpenShift 4.11+
- **🐳 Pod Network Isolation**: Capture traffic from specific pod network namespaces using `nsenter`
- **📝 Complete Audit Trail**: Logs all command executions with user, timestamp, node, and pod details
- **🚨 Real-time Alerts**: Immediate notifications for privilege violations and unauthorized access
- **🎛️ Command Validation**: Only allows `tcpdump` and `ncat` with safety parameter enforcement
- **🔧 Shell-based**: Easy to extend and customize using familiar bash scripts
- **📊 Monitoring Ready**: Comprehensive audit logging and violation detection
- **🏗️ OpenShift Native**: Uses `oc debug node` - no persistent privileged containers required

## 🚀 Quick Start

### Prerequisites
- OpenShift cluster 4.11+ (baremetal implementation)
- OpenShift CLI (`oc`) installed and logged in
- Cluster-admin privileges for initial setup and node debugging
- Target pods and nodes must be accessible

### Installation
```bash
# Clone the repository
git clone <repository-url>
cd debugger

# Basic setup (no persistent resources required)
./scripts/install.sh

# Set up GitHub Actions testing (optional)
./scripts/setup-github-secrets.sh

# Test the solution
./scripts/test-solution.sh
```

### 🤖 Automated Testing
This solution includes comprehensive GitHub Actions workflows for continuous testing:

```bash
# Set up automated testing on your OpenShift cluster
./scripts/setup-github-secrets.sh

# Manual workflow triggers available:
# - basic: Quick validation
# - full: Complete testing with actual command execution  
# - namespace-admin-only: Test namespace admin user experience
```

**Benefits of Automated Testing:**
- ✅ **Continuous Validation**: Automatically tests changes on real OpenShift clusters
- ✅ **Permission Testing**: Validates both cluster-admin and namespace admin scenarios
- ✅ **Multi-environment**: Test across development, staging, and production clusters
- ✅ **Compliance Reports**: Generate detailed test reports for audit purposes

### Basic Usage
```bash
# Debug specific pod network namespace
./scripts/execute-command.sh worker-node-1 my-app-pod default tcpdump -i eth0 -c 100

# Debug another pod's network traffic
./scripts/execute-command.sh worker-node-1 web-server default tcpdump -i eth0 port 80

# Test connectivity from pod's network context
./scripts/execute-command.sh worker-node-2 client-pod default ncat -zv service-host 80

# Debug node-level network (host network namespace)
./scripts/execute-command.sh worker-node-2 - - tcpdump -i eth0 -c 100

# View audit logs
./scripts/audit-viewer.sh recent 50

# Check for security violations
./scripts/audit-viewer.sh violations
```

## 📁 Repository Structure

```
debugger/
├── k8s/                          # OpenShift resource definitions (legacy)
│   ├── scc.yaml                  # Security Context Constraints (not needed with oc debug)
│   ├── rbac.yaml                 # Role-Based Access Control (basic requirements)
│   ├── configmap.yaml            # Command validation scripts (legacy)
│   ├── daemonset.yaml            # Privileged container deployment (legacy)
│   └── job-template.yaml         # Job template (replaced by oc debug)
├── scripts/                      # Management scripts
│   ├── install.sh                # Basic setup script (minimal requirements)
│   ├── execute-command.sh        # Command execution using oc debug node
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

## 🏗️ Architecture

This solution implements the **Red Hat recommended approach** for network debugging in OpenShift 4.11+:

### Core Components
1. **`oc debug node`**: Creates temporary debug pods on target worker nodes
2. **`nsenter`**: Enters specific pod network namespaces for isolated debugging
3. **`crictl`**: Container runtime interface for pod inspection and namespace detection
4. **Shell Scripts**: Command validation, audit logging, and user interface

### Network Namespace Isolation
- **Pod-specific debugging**: Uses `crictl inspectp` to find pod network namespace paths
- **nsenter integration**: Executes commands within target pod's network context
- **Host network fallback**: Supports node-level debugging when no specific pod is targeted

### Security Model
- **No persistent privileged containers**: Uses temporary debug pods only when needed
- **Built-in OpenShift security**: Leverages `oc debug` security model
- **Command validation**: Pre-execution filtering of dangerous operations
- **Audit logging**: Complete traceability of all debugging activities

## 🛡️ Security Features

### Command Validation
- **Allowed Commands**: Only `tcpdump` and `ncat`
- **Blocked Operations**: File writes (outside safe paths), command execution, pipe operations
- **Safety Parameters**: Automatic limits for packet capture counts
- **Path Restrictions**: tcpdump output files must be in `/host/var/tmp/`

### Access Control
- **OpenShift Native**: Uses `oc debug node` built-in access control
- **User Authentication**: Leverages existing OpenShift authentication
- **Namespace Validation**: Ensures pods exist in specified namespaces
- **Node Access Control**: Standard OpenShift node access permissions

### Network Isolation
- **Pod Network Namespace**: Captures traffic only from target pod's network context
- **No Cross-pod Access**: Network namespace isolation prevents accessing other pods
- **Host Network Option**: Controlled host-level debugging when explicitly requested

### Audit and Monitoring
- **Comprehensive Logging**: All executions logged with user, node, pod, and command details
- **Real-time Tracking**: Immediate logging of command attempts and results
- **File System Audit**: Tracks pcap file creation and access
- **Violation Detection**: Logs and alerts on prohibited command attempts

## 📖 Documentation

- **[Complete Documentation](docs/README.md)**: Detailed architecture and configuration
- **[User Guide](docs/USER_GUIDE.md)**: How to use the debugging tools
- **[Administrator Guide](docs/ADMIN_GUIDE.md)**: Installation, configuration, and maintenance

## 🔧 Common Use Cases

### Pod-specific Network Debugging
```bash
# Capture HTTP traffic from specific pod
./scripts/execute-command.sh worker-1 web-server default tcpdump -i eth0 -c 50 port 80

# Check database connectivity from application pod
./scripts/execute-command.sh worker-1 app-pod myapp ncat -zv database-server 5432

# Monitor DNS queries from specific pod
./scripts/execute-command.sh worker-1 client-pod default tcpdump -i eth0 -c 20 port 53

# Capture all traffic from pod's network namespace
./scripts/execute-command.sh worker-1 debug-pod default tcpdump -i eth0 -c 100
```

### Service and Connectivity Testing
```bash
# Test load balancer connectivity from pod context
./scripts/execute-command.sh worker-1 client-pod default ncat -zv load-balancer 443

# Capture traffic to specific service from pod
./scripts/execute-command.sh worker-1 web-pod default tcpdump -i eth0 -c 100 host service-ip

# Check port range accessibility from pod
./scripts/execute-command.sh worker-1 test-pod default ncat -z service-host 8080-8090

# Save pcap file for analysis
./scripts/execute-command.sh worker-1 app-pod default tcpdump -i eth0 -w /host/var/tmp/debug.pcap -c 1000
```

### Node-level Debugging
```bash
# Debug node's host network (when pod context is not needed)
./scripts/execute-command.sh worker-2 - - tcpdump -i eth0 -c 100

# Check node-level connectivity
./scripts/execute-command.sh worker-2 - - ncat -zv external-service 443
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

### Local Testing
The solution includes comprehensive local tests:

```bash
# Run all tests locally
./scripts/test-solution.sh

# Run tests with detailed output
./scripts/test-solution.sh --verbose
```

### Automated CI/CD Testing
GitHub Actions workflows provide continuous testing on live OpenShift clusters:

```bash
# Set up automated testing (one-time setup)
./scripts/setup-github-secrets.sh
```

**Test Scenarios:**
- 🔵 **Basic Testing**: Script validation, parameter checking, RBAC syntax
- 🟢 **Full Testing**: Complete solution including actual command execution
- 🟡 **Namespace Admin**: Tests user experience with limited permissions

**Test Coverage:**
- ✅ **Permission Scenarios**: Both cluster-admin and namespace admin access
- ✅ **OpenShift Compatibility**: Validates version 4.11+ features
- ✅ **Command Execution**: Tests tcpdump and ncat in real environments  
- ✅ **Error Handling**: Validates graceful permission limitation handling
- ✅ **Security Controls**: Command validation and audit logging
- ✅ **Cross-Environment**: Supports multiple cluster configurations

**Viewing Results:**
- GitHub Actions tab shows real-time test execution
- Detailed test reports available as workflow artifacts
- Failed tests include logs for troubleshooting

Tests verify:
- ✅ Red Hat solution compatibility (oc debug node approach)
- ✅ Network namespace isolation functionality
- ✅ Command validation and security controls
- ✅ Audit logging and monitoring capabilities
- ✅ RBAC configuration and permissions
- ✅ Error handling for insufficient privileges

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