# Administrator Guide: Network Debugger Solution

## Overview

This guide provides administrators with information on installing, configuring, monitoring, and maintaining the OpenShift network debugging solution.

## Installation

### Prerequisites

- OpenShift cluster with sufficient resources
- Cluster administrator privileges
- OpenShift CLI (`oc`) version 4.6 or later
- Worker nodes with network interfaces accessible

### Installation Steps

1. **Prepare the Environment**
   ```bash
   # Ensure you have cluster-admin privileges
   oc auth can-i create securitycontextconstraints
   
   # Create or verify namespace exists
   oc create namespace fttc-ancillary --dry-run=client -o yaml | oc apply -f -
   ```

2. **Install the Solution**
   ```bash
   # Clone the repository
   git clone <repository-url>
   cd debugger
   
   # Run the installation script
   ./scripts/install.sh
   ```

3. **Setup Monitoring and Alerting**
   ```bash
   # Configure monitoring
   ./scripts/setup-monitoring.sh
   
   # Setup email alerts (optional)
   export ALERT_EMAIL="admin@example.com"
   ./scripts/setup-monitoring.sh --alerting
   
   # Setup Slack alerts (optional)
   export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/..."
   ./scripts/setup-monitoring.sh --alerting
   ```

4. **Verify Installation**
   ```bash
   # Check all resources
   oc get all -n fttc-ancillary -l app=debugger-daemon
   
   # Verify SCC
   oc get scc debugger-privileged-scc
   
   # Test basic functionality
   ./scripts/execute-command.sh $(oc get nodes -o name | head -1 | cut -d/ -f2) tcpdump -c 5 -i lo
   ```

## Configuration

### Security Context Constraints

The solution uses a custom SCC with these capabilities:
- `NET_ADMIN`: Network administration
- `NET_RAW`: Raw socket access
- `SYS_ADMIN`: System administration
- `SYS_PTRACE`: Process tracing

**File**: `k8s/scc.yaml`

```yaml
allowedCapabilities:
- NET_ADMIN
- NET_RAW
- SYS_ADMIN
- SYS_PTRACE
allowPrivilegedContainer: true
allowHostNetwork: true
allowHostPID: true
```

### RBAC Configuration

The solution implements layered RBAC:

1. **Namespace-scoped Role** (`debugger-role`):
   - Manage pods and jobs in `fttc-ancillary` namespace
   - Access to specific ConfigMaps for audit logging
   - Create events for monitoring

2. **Cluster-scoped Role** (`debugger-node-access`):
   - Read access to nodes
   - Limited pod management with specific naming pattern

**Customizing Access**:
```bash
# Add users to the solution
oc edit rolebinding debugger-rolebinding -n fttc-ancillary

# Add user or group
subjects:
- kind: User
  name: developer@example.com
  apiGroup: rbac.authorization.k8s.io
- kind: Group
  name: network-debug-team
  apiGroup: rbac.authorization.k8s.io
```

### Command Validation

Commands are validated through the `command-validator.sh` script in the ConfigMap.

**Allowed Commands**: `tcpdump`, `ncat`

**Blocked Operations**:
- File writes (`-w`, `>`, `>>`)
- Command execution (`exec`, `system`)
- Pipe operations (`|`)
- Dangerous options specific to each tool

**Customizing Validation**:
```bash
# Edit the ConfigMap
oc edit configmap debugger-scripts -n fttc-ancillary

# Modify the command-validator.sh section
# Add new commands to ALLOWED_COMMANDS array
# Add validation logic for new commands
```

## Monitoring and Maintenance

### Audit Log Management

#### Viewing Audit Logs
```bash
# Recent activity
./scripts/audit-viewer.sh recent 100

# Specific user activity
./scripts/audit-viewer.sh user john.doe@example.com

# Security violations only
./scripts/audit-viewer.sh violations

# Generate detailed report
./scripts/audit-viewer.sh report 24  # Last 24 hours
```

#### Audit Log Format
```json
{
  "timestamp": "2024-01-15T10:30:45Z",
  "user": "developer@example.com",
  "node": "worker-node-1",
  "action": "EXECUTE",
  "command": "tcpdump -i eth0 -c 100"
}
```

#### Log Retention
- Container logs: Managed by OpenShift logging configuration
- Host path logs: Located in `/var/log/debugger/` on each node
- Automatic cleanup: Jobs are deleted after 1 hour (`ttlSecondsAfterFinished: 3600`)

### Resource Monitoring

#### DaemonSet Health
```bash
# Check DaemonSet status
oc get daemonset debugger-daemon -n fttc-ancillary

# View pod status on all nodes
oc get pods -l app=debugger-daemon -n fttc-ancillary -o wide

# Check resource usage
oc top pods -l app=debugger-daemon -n fttc-ancillary
```

#### Job Monitoring
```bash
# Active jobs
oc get jobs -n fttc-ancillary

# Failed jobs
oc get jobs -n fttc-ancillary --field-selector status.successful=0

# Job history
oc get events -n fttc-ancillary --field-selector involvedObject.kind=Job
```

### Performance Tuning

#### Resource Limits
Current limits (per pod):
- Memory: 128Mi (request), 256Mi (limit)
- CPU: 100m (request), 200m (limit)

**Adjusting Limits**:
```bash
# Edit DaemonSet
oc edit daemonset debugger-daemon -n fttc-ancillary

# Update resources section
resources:
  requests:
    memory: "256Mi"
    cpu: "200m"
  limits:
    memory: "512Mi"
    cpu: "500m"
```

#### Node Selection
By default, the DaemonSet runs on all worker nodes. To limit to specific nodes:

```bash
# Edit DaemonSet
oc edit daemonset debugger-daemon -n fttc-ancillary

# Add node selector
nodeSelector:
  node-role.kubernetes.io/worker: ""
  debug-enabled: "true"

# Label nodes for debugging
oc label node worker-node-1 debug-enabled=true
```

## Security Management

### Access Control

#### Adding/Removing Users
```bash
# View current users
oc get rolebinding debugger-rolebinding -n fttc-ancillary -o yaml

# Add user
oc patch rolebinding debugger-rolebinding -n fttc-ancillary --type='json' \
  -p='[{"op": "add", "path": "/subjects/-", "value": {"kind": "User", "name": "newuser@example.com", "apiGroup": "rbac.authorization.k8s.io"}}]'

# Remove user (replace index with appropriate number)
oc patch rolebinding debugger-rolebinding -n fttc-ancillary --type='json' \
  -p='[{"op": "remove", "path": "/subjects/1"}]'
```

#### Group-based Access
```bash
# Create group-based access
oc create rolebinding debugger-group-access \
  --role=debugger-role \
  --group=network-debug-team \
  -n fttc-ancillary
```

### Security Auditing

#### Regular Security Checks
```bash
# Check for privilege violations
./scripts/audit-viewer.sh violations | tail -10

# Review user activity
./scripts/audit-viewer.sh report 168  # Weekly report

# Check for unusual patterns
oc logs -l app=debugger-daemon -n fttc-ancillary --since=24h | grep VIOLATION
```

#### Security Incident Response
1. **Identify the violation**: Use audit logs to determine scope
2. **Immediate response**: Disable user access if necessary
3. **Investigation**: Gather detailed logs and evidence
4. **Remediation**: Apply security patches or configuration changes
5. **Documentation**: Record incident and lessons learned

### Alerting Configuration

#### Prometheus Alerts
The solution includes pre-configured alerts:

- **DebuggerPrivilegeViolation**: Critical alert for security violations
- **DebuggerUnauthorizedCommand**: Warning for blocked commands
- **DebuggerDaemonDown**: Warning for daemon failures
- **DebuggerHighJobFailureRate**: Warning for excessive failures

#### Custom Alert Rules
```yaml
# Add to monitoring/prometheus-rules.yaml
- alert: DebuggerSuspiciousActivity
  expr: rate(debugger_violations_total[1h]) > 5
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "High violation rate detected"
    description: "More than 5 violations per hour detected"
```

#### Email Notifications
```bash
# Configure email alerts
export ALERT_EMAIL="security-team@example.com"
./scripts/setup-monitoring.sh --alerting

# Test email configuration
echo "Test alert" | mail -s "Debugger Test Alert" $ALERT_EMAIL
```

## Troubleshooting

### Common Issues

#### 1. DaemonSet Pods Not Starting
```bash
# Check events
oc describe daemonset debugger-daemon -n fttc-ancillary

# Common causes:
# - SCC not properly assigned
# - Node selector issues
# - Resource constraints
# - Image pull failures

# Solutions:
# Check SCC assignment
oc get scc debugger-privileged-scc -o yaml | grep users

# Verify node labels
oc get nodes --show-labels | grep worker
```

#### 2. Command Execution Failures
```bash
# Check job status
oc get jobs -n fttc-ancillary

# View job logs
oc logs -l app=debugger-job -n fttc-ancillary

# Common causes:
# - Command validation failures
# - Node selector issues
# - Resource limits exceeded
# - Network policies blocking access
```

#### 3. Audit Logs Missing
```bash
# Check daemon pod logs
oc logs -l app=debugger-daemon -n fttc-ancillary

# Verify log directory
oc exec -it <daemon-pod> -n fttc-ancillary -- ls -la /var/log/

# Check host path mounts
oc describe pod <daemon-pod> -n fttc-ancillary | grep -A5 -B5 Mounts
```

#### 4. Permission Denied Errors
```bash
# Check service account permissions
oc auth can-i create jobs --as=system:serviceaccount:fttc-ancillary:debugger-sa

# Verify SCC assignment
oc describe scc debugger-privileged-scc | grep Users

# Check user permissions
oc auth can-i create jobs -n fttc-ancillary
```

### Diagnostic Commands

```bash
# Complete system check
./scripts/install.sh --verify

# Monitoring status
./scripts/setup-monitoring.sh --status

# Resource usage
oc top pods -n fttc-ancillary
oc top nodes

# Network policies
oc get networkpolicy -n fttc-ancillary

# Security context
oc get pods -l app=debugger-daemon -n fttc-ancillary -o yaml | grep -A10 securityContext
```

## Backup and Recovery

### Configuration Backup
```bash
# Backup all configurations
mkdir -p backup/$(date +%Y%m%d)
oc get scc debugger-privileged-scc -o yaml > backup/$(date +%Y%m%d)/scc.yaml
oc get all,configmap,secret,sa,role,rolebinding -n fttc-ancillary -o yaml > backup/$(date +%Y%m%d)/namespace.yaml
```

### Disaster Recovery
```bash
# Restore from backup
oc apply -f backup/20240115/scc.yaml
oc apply -f backup/20240115/namespace.yaml
```

## Upgrade Procedures

### Updating the Solution
1. **Backup current configuration**
2. **Test in non-production environment**
3. **Schedule maintenance window**
4. **Update container images**
5. **Apply configuration changes**
6. **Verify functionality**
7. **Monitor for issues**

### Rolling Updates
```bash
# Update DaemonSet image
oc patch daemonset debugger-daemon -n fttc-ancillary \
  -p='{"spec":{"template":{"spec":{"containers":[{"name":"debugger","image":"new-image:tag"}]}}}}'

# Monitor rollout
oc rollout status daemonset/debugger-daemon -n fttc-ancillary
```

## Performance and Scaling

### Capacity Planning
- **Nodes**: Each worker node runs one daemon pod
- **Jobs**: Multiple concurrent jobs supported
- **Storage**: Audit logs stored on each node's local storage
- **Network**: Minimal network overhead for management traffic

### Scaling Considerations
- DaemonSet automatically scales with cluster size
- Job concurrency limited by node resources
- Audit log storage grows with usage
- Monitoring overhead scales with number of nodes and jobs

## Compliance and Governance

### Audit Requirements
- All command executions are logged
- User identity tracking
- Timestamp accuracy
- Command parameter recording
- Success/failure status

### Regular Reviews
- Monthly audit log analysis
- Quarterly access review
- Annual security assessment
- Regular vulnerability scanning

### Documentation Maintenance
- Keep user guides updated
- Document configuration changes
- Maintain incident response playbooks
- Update security procedures

## Support and Escalation

### Internal Support
1. Check this administrator guide
2. Review audit logs and monitoring
3. Use diagnostic commands
4. Check OpenShift documentation

### Escalation Path
1. **Level 1**: Application team lead
2. **Level 2**: Platform team
3. **Level 3**: Security team
4. **Level 4**: Vendor support (if applicable)

### Documentation
- Maintain incident logs
- Document configuration changes
- Keep contact information updated
- Record lessons learned