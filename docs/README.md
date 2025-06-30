# OpenShift Network Debugger Solution

## Overview

This solution provides controlled access to network debugging tools (`tcpdump` and `ncat`) on OpenShift worker nodes for application teams with limited cluster access. It ensures security through proper RBAC, command validation, audit logging, and privilege violation alerting.

## Key Features

- ✅ **Controlled Command Execution**: Only `tcpdump` and `ncat` commands are allowed
- ✅ **Security Context Constraints**: Proper OpenShift SCC for privileged container access
- ✅ **RBAC Integration**: Role-based access control aligned with OpenShift security
- ✅ **Audit Logging**: Comprehensive logging of all command executions and violations
- ✅ **Privilege Violation Alerts**: Real-time alerting for unauthorized access attempts
- ✅ **Node-level Access**: Execute commands directly on worker nodes
- ✅ **Easy Extension**: Shell-based scripts for easy customization

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        OpenShift Cluster                        │
├─────────────────────────────────────────────────────────────────┤
│  fttc-ancillary Namespace                                      │
│  ┌─────────────────┐  ┌─────────────────┐                     │
│  │   Application   │  │   Debugger      │                     │
│  │   Team User     │──│   Scripts       │                     │
│  │                 │  │                 │                     │
│  └─────────────────┘  └─────────────────┘                     │
│           │                     │                              │
│           ▼                     ▼                              │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              Job Template                               │   │
│  │  (Command Validation + Execution)                      │   │
│  └─────────────────────────────────────────────────────────┘   │
├─────────────────────────────────────────────────────────────────┤
│  Worker Nodes                                                   │
│  ┌─────────────────┐  ┌─────────────────┐                     │
│  │  Node 1         │  │  Node 2         │                     │
│  │ ┌─────────────┐ │  │ ┌─────────────┐ │                     │
│  │ │ Debugger    │ │  │ │ Debugger    │ │                     │
│  │ │ DaemonSet   │ │  │ │ DaemonSet   │ │                     │
│  │ │ Pod         │ │  │ │ Pod         │ │                     │
│  │ └─────────────┘ │  │ └─────────────┘ │                     │
│  └─────────────────┘  └─────────────────┘                     │
└─────────────────────────────────────────────────────────────────┘
            │                         │
            ▼                         ▼
┌─────────────────────────────────────────────────────────────────┐
│              Monitoring & Alerting                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐ │
│  │ Prometheus  │  │ Audit Logs  │  │ Security Alerts         │ │
│  │ Metrics     │  │ Collection  │  │ (Email/Slack/Syslog)   │ │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

## Components

### 1. Security Context Constraints (SCC)
- **File**: `k8s/scc.yaml`
- **Purpose**: Defines privileged access permissions for the debugger containers
- **Capabilities**: NET_ADMIN, NET_RAW, SYS_ADMIN, SYS_PTRACE

### 2. RBAC Resources
- **File**: `k8s/rbac.yaml`
- **Components**:
  - ServiceAccount: `debugger-sa`
  - Role: `debugger-role` (namespace-scoped)
  - ClusterRole: `debugger-node-access` (cluster-scoped)
  - RoleBindings and ClusterRoleBindings

### 3. DaemonSet
- **File**: `k8s/daemonset.yaml`
- **Purpose**: Runs privileged containers on all worker nodes
- **Features**: Host network access, audit logging, resource limits

### 4. Job Template
- **File**: `k8s/job-template.yaml`
- **Purpose**: Template for creating command execution jobs
- **Security**: Command validation, user tracking, audit logging

### 5. Scripts
- **install.sh**: Main installation script
- **execute-command.sh**: Command execution interface
- **audit-viewer.sh**: Audit log viewer and analyzer
- **setup-monitoring.sh**: Monitoring and alerting setup

## Quick Start

### 1. Prerequisites

- OpenShift cluster with admin access
- OpenShift CLI (`oc`) installed and configured
- Access to the `fttc-ancillary` namespace

### 2. Installation

```bash
# Clone the repository
git clone <repository-url>
cd debugger

# Install the solution (requires cluster-admin privileges)
./scripts/install.sh

# Setup monitoring and alerting
./scripts/setup-monitoring.sh
```

### 3. Usage

```bash
# Execute tcpdump on a specific node
./scripts/execute-command.sh worker-node-1 tcpdump -i eth0 -c 100

# Execute ncat on a specific node
./scripts/execute-command.sh worker-node-2 ncat -l 8080

# View audit logs
./scripts/audit-viewer.sh recent 50

# Check for violations
./scripts/audit-viewer.sh violations

# Generate audit report
./scripts/audit-viewer.sh report 24
```

## Security Features

### Command Validation
- Only `tcpdump` and `ncat` commands are permitted
- Dangerous options are blocked (e.g., file writes, command execution)
- Default safety parameters are applied

### Audit Logging
- All command executions are logged with:
  - User identity
  - Node name
  - Command and arguments
  - Timestamp
  - Success/failure status

### Privilege Violation Detection
- Unauthorized commands are blocked and logged
- Real-time alerts for security violations
- Integration with Prometheus, email, and Slack

### Access Control
- RBAC-based permissions
- Service account isolation
- Namespace-scoped access

## Configuration

### Environment Variables

```bash
# Email alerting
export ALERT_EMAIL="security@example.com"

# Slack notifications
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/..."

# Log forwarding
export LOG_FORWARDING_HOST="log-server.example.com"
export LOG_FORWARDING_PORT="24224"
```

### Customization

The solution can be easily extended by modifying:

1. **Allowed Commands**: Edit `command-validator.sh` in the ConfigMap
2. **RBAC Permissions**: Modify `k8s/rbac.yaml`
3. **Alerting Rules**: Update `monitoring/prometheus-rules.yaml`
4. **Command Validation**: Enhance validation logic in scripts

## Monitoring and Alerting

### Prometheus Integration
- ServiceMonitor for metrics collection
- PrometheusRule for alerting rules
- Custom metrics for violations and command executions

### Log Analysis
```bash
# View recent audit logs
./scripts/audit-viewer.sh recent

# Monitor live logs
./scripts/audit-viewer.sh follow

# Generate detailed reports
./scripts/audit-viewer.sh report 48
```

### Alert Types
- **Critical**: Privilege violations
- **Warning**: Unauthorized command attempts
- **Warning**: Daemon pod failures
- **Warning**: High job failure rates

## Troubleshooting

### Common Issues

1. **SCC Creation Failed**
   ```bash
   # Check cluster-admin privileges
   oc auth can-i create securitycontextconstraints
   ```

2. **DaemonSet Pods Not Starting**
   ```bash
   # Check pod status and events
   oc get pods -l app=debugger-daemon -n fttc-ancillary
   oc describe pod <pod-name> -n fttc-ancillary
   ```

3. **Command Execution Fails**
   ```bash
   # Check job logs
   oc logs -l app=debugger-job -n fttc-ancillary
   ```

4. **No Audit Logs**
   ```bash
   # Check daemon pod logs
   oc logs -l app=debugger-daemon -n fttc-ancillary
   ```

### Verification Commands

```bash
# Check all resources
oc get all -l app=debugger-daemon -n fttc-ancillary

# Verify SCC
oc get scc debugger-privileged-scc

# Check RBAC
oc get role,rolebinding,clusterrole,clusterrolebinding | grep -i debugger

# Test command execution
./scripts/execute-command.sh $(oc get nodes -o name | head -1 | cut -d/ -f2) tcpdump -i lo -c 5
```

## Maintenance

### Regular Tasks

1. **Review Audit Logs**: Weekly review of command executions and violations
2. **Update Allowed Commands**: As needed, modify validation scripts
3. **Monitor Resource Usage**: Check DaemonSet resource consumption
4. **Security Updates**: Keep container images updated

### Cleanup

```bash
# Uninstall the solution
./scripts/install.sh --uninstall

# Remove monitoring components
oc delete -f monitoring/ -n fttc-ancillary
```

## Support

For issues or feature requests:
1. Check the troubleshooting section
2. Review audit logs for security violations
3. Consult OpenShift documentation for SCC and RBAC issues
4. Contact the platform team for cluster-level permissions

## Security Considerations

- This solution provides privileged access to worker nodes
- Regular audit log review is essential
- Monitor for privilege escalation attempts
- Keep the solution updated with security patches
- Implement proper backup and disaster recovery procedures

## License

This solution is provided as-is for OpenShift environments. Review and adapt according to your organization's security policies.