# User Guide: Network Debugging on OpenShift

## Overview

This guide explains how to use the network debugging solution to run `tcpdump` and `ncat` commands on OpenShift worker nodes.

## Prerequisites

- Access to the `fttc-ancillary` namespace in OpenShift
- OpenShift CLI (`oc`) installed and configured
- Basic knowledge of `tcpdump` and `ncat` commands

## Getting Started

### 1. Login to OpenShift

```bash
oc login <your-cluster-url>
```

### 2. Verify Access

```bash
# Check if you can access the namespace
oc get pods -n fttc-ancillary

# List available worker nodes
oc get nodes --no-headers | grep worker
```

## Available Commands

The debugging solution supports two network tools:

### tcpdump
Network packet capture and analysis tool.

**Common Options:**
- `-i <interface>`: Capture on specific network interface
- `-c <count>`: Capture specified number of packets
- `-n`: Don't resolve addresses to names
- `-v`: Verbose output
- `-s <snaplen>`: Capture snapshot length
- `host <hostname>`: Filter by host
- `port <port>`: Filter by port

### ncat
Network utility for reading/writing network connections.

**Common Options:**
- `-l`: Listen mode
- `-p <port>`: Specify port
- `-u`: UDP mode (default is TCP)
- `-v`: Verbose output
- `-z`: Zero-I/O mode (port scanning)

## Usage Examples

### Basic tcpdump Examples

```bash
# Capture 100 packets on eth0 interface
./scripts/execute-command.sh worker-node-1 tcpdump -i eth0 -c 100

# Capture HTTP traffic
./scripts/execute-command.sh worker-node-1 tcpdump -i eth0 -c 50 port 80

# Capture traffic to/from specific host
./scripts/execute-command.sh worker-node-1 tcpdump -i eth0 -c 20 host 10.0.0.1

# Capture with verbose output and no name resolution
./scripts/execute-command.sh worker-node-1 tcpdump -i eth0 -c 30 -n -v

# Capture ICMP packets (ping)
./scripts/execute-command.sh worker-node-1 tcpdump -i eth0 -c 10 icmp
```

### Basic ncat Examples

```bash
# Test TCP connectivity to a service
./scripts/execute-command.sh worker-node-1 ncat -zv service-host 80

# Test UDP connectivity
./scripts/execute-command.sh worker-node-1 ncat -zuv service-host 53

# Listen on TCP port (for connectivity testing)
./scripts/execute-command.sh worker-node-1 ncat -l 8080

# Scan multiple ports
./scripts/execute-command.sh worker-node-1 ncat -z service-host 80-85
```

## Advanced Usage

### Finding the Right Node

```bash
# List all worker nodes
oc get nodes -l node-role.kubernetes.io/worker=''

# Find which node a pod is running on
oc get pods -o wide -n your-namespace

# Get node details
oc describe node <node-name>
```

### Network Interface Discovery

```bash
# List network interfaces on a node
./scripts/execute-command.sh worker-node-1 tcpdump -D

# Quick test to identify active interfaces
./scripts/execute-command.sh worker-node-1 tcpdump -i any -c 5
```

### Troubleshooting Common Network Issues

#### 1. Service Connectivity Issues

```bash
# Test if service is reachable from node
./scripts/execute-command.sh worker-node-1 ncat -zv service-name.namespace.svc.cluster.local 80

# Capture traffic while testing connectivity
./scripts/execute-command.sh worker-node-1 tcpdump -i eth0 -c 20 host service-ip
```

#### 2. DNS Resolution Problems

```bash
# Check DNS traffic
./scripts/execute-command.sh worker-node-1 tcpdump -i eth0 -c 10 port 53

# Test DNS connectivity
./scripts/execute-command.sh worker-node-1 ncat -zuv dns-server-ip 53
```

#### 3. Load Balancer Issues

```bash
# Monitor traffic to load balancer
./scripts/execute-command.sh worker-node-1 tcpdump -i eth0 -c 50 host lb-ip

# Test connectivity to backend servers
./scripts/execute-command.sh worker-node-1 ncat -zv backend-server 8080
```

#### 4. SSL/TLS Connection Issues

```bash
# Capture HTTPS traffic
./scripts/execute-command.sh worker-node-1 tcpdump -i eth0 -c 30 port 443

# Test SSL connectivity
./scripts/execute-command.sh worker-node-1 ncat -zv ssl-server 443
```

## Security and Compliance

### Audit Logging

All your commands are logged for security and compliance purposes. The logs include:
- Your username
- Timestamp of execution
- Node where command was executed
- Full command with arguments
- Success/failure status

### Viewing Your Audit Trail

```bash
# View your recent command history
./scripts/audit-viewer.sh user $(oc whoami) 20

# View all recent audit logs
./scripts/audit-viewer.sh recent 50
```

### Command Restrictions

For security reasons, certain command options are restricted:

#### tcpdump Restrictions
- Cannot write to files (`-w` option is blocked)
- Output redirection (`>`, `>>`) is blocked
- Pipe operations (`|`) are blocked
- Command execution options are blocked

#### ncat Restrictions
- Command execution options (`--exec`, `-e`) are blocked
- Shell execution (`--sh-exec`) is blocked
- Output redirection and pipes are blocked

#### General Restrictions
- Only `tcpdump` and `ncat` commands are allowed
- All other commands will be blocked and logged as violations
- Command injection attempts are detected and blocked

## Best Practices

### 1. Use Appropriate Packet Counts
```bash
# Good: Limited packet count
./scripts/execute-command.sh worker-node-1 tcpdump -i eth0 -c 100

# Avoid: Unlimited capture (may be automatically limited)
./scripts/execute-command.sh worker-node-1 tcpdump -i eth0
```

### 2. Be Specific with Filters
```bash
# Good: Specific filter
./scripts/execute-command.sh worker-node-1 tcpdump -i eth0 -c 20 host 10.0.0.1 and port 80

# Less efficient: Broad capture
./scripts/execute-command.sh worker-node-1 tcpdump -i eth0 -c 1000
```

### 3. Clean Up After Testing
- Jobs are automatically cleaned up after 1 hour
- Long-running commands may be terminated by administrators
- Use appropriate timeout values for your testing

## Troubleshooting

### Common Error Messages

#### "Command not allowed"
```
ERROR: Command 'ping' is not allowed. Only tcpdump and ncat are permitted.
```
**Solution**: Use only `tcpdump` or `ncat` commands.

#### "Node not found"
```
ERROR: Node 'invalid-node' does not exist or is not accessible
```
**Solution**: Check available nodes with `oc get nodes`.

#### "Job creation failed"
```
ERROR: Failed to create job
```
**Solution**: Check your permissions and namespace access.

#### "Dangerous options detected"
```
ERROR: Dangerous tcpdump options detected
```
**Solution**: Remove restricted options like `-w`, `>`, `|`, etc.

### Getting Help

1. **List available nodes:**
   ```bash
   oc get nodes -l node-role.kubernetes.io/worker=''
   ```

2. **Check your permissions:**
   ```bash
   oc auth can-i create jobs -n fttc-ancillary
   ```

3. **View recent command executions:**
   ```bash
   ./scripts/audit-viewer.sh user $(oc whoami) 10
   ```

4. **Check job status:**
   ```bash
   oc get jobs -n fttc-ancillary
   ```

## Command Reference

### execute-command.sh Syntax
```bash
./scripts/execute-command.sh <node-name> <command> [arguments...]
```

### Examples by Use Case

| Use Case | Command |
|----------|---------|
| Web service connectivity | `./scripts/execute-command.sh worker-1 ncat -zv web-server 80` |
| Database connection test | `./scripts/execute-command.sh worker-1 ncat -zv db-server 5432` |
| HTTP traffic analysis | `./scripts/execute-command.sh worker-1 tcpdump -i eth0 -c 50 port 80` |
| DNS troubleshooting | `./scripts/execute-command.sh worker-1 tcpdump -i eth0 -c 10 port 53` |
| Network interface check | `./scripts/execute-command.sh worker-1 tcpdump -D` |
| ICMP/ping analysis | `./scripts/execute-command.sh worker-1 tcpdump -i eth0 -c 10 icmp` |

## Support

If you encounter issues:

1. Check this user guide first
2. Review the troubleshooting section
3. Check your audit logs for any violations
4. Contact your platform administrator
5. Provide specific error messages and command details when requesting help

Remember: All debugging activities are logged and monitored for security purposes.