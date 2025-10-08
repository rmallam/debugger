# Debugger Jobs Monitoring Setup

## Overview
The enhanced `run-debugger-job.sh` now includes a sidecar container that monitors logs from the main debugger container and exposes Prometheus metrics for alerting.

## Architecture

### Main Container (debugger)
- Executes the debugging commands (tcpdump, ncat, ip, ifconfig)
- Writes logs to shared volume at `/tmp/shared-logs/debugger.log`

### Sidecar Container (log-metrics-sidecar)
- Monitors logs from main container
- Exposes Prometheus metrics on port 9090
- Provides real-time job status and error tracking

## Metrics Exposed

### debugger_job_status
- **Type**: Gauge
- **Values**: 
  - `-1`: Job failed
  - `0`: Job running
  - `1`: Job completed successfully
- **Labels**: job_name, command, user, node

### debugger_job_duration_seconds
- **Type**: Gauge
- **Description**: Duration of job execution in seconds
- **Labels**: job_name, command, user, node

### debugger_command_errors_total
- **Type**: Counter
- **Description**: Total number of command errors detected
- **Labels**: job_name, command, user, node

### debugger_pcap_files_generated_total
- **Type**: Counter
- **Description**: Total number of pcap files generated (tcpdump only)
- **Labels**: job_name, command, user, node

## Alerts Configured

1. **DebuggerJobFailed**: Triggers when job status is -1
2. **DebuggerJobRunningTooLong**: Triggers when job runs longer than 10 minutes
3. **DebuggerCommandErrors**: Triggers when errors are detected in logs
4. **DebuggerHighJobVolume**: Triggers on high job creation rate

## Setup Instructions

1. **Apply ServiceMonitor** (if using Prometheus Operator):
   ```bash
   kubectl apply -f monitoring/debugger-servicemonitor.yaml
   ```

2. **Apply AlertManager Rules**:
   ```bash
   kubectl apply -f monitoring/debugger-alerts.yaml
   ```

3. **Modify execute-command.sh**:
   - Add logging to shared volume (see execute-command-logging.sh example)
   - Ensure structured log messages for proper parsing

4. **Test the setup**:
   ```bash
   # Run a test job
   ./run-debugger-job.sh node1 test-pod default tcpdump 30
   
   5. **Check metrics endpoint during job execution**:
   ```bash
   kubectl get pods -n debugger -l app=debugger-job
   kubectl port-forward <pod-name> 9090:9090 -n debugger
   curl http://localhost:9090
   ```
   ```

## Benefits

- **Real-time monitoring**: Track job execution status and duration
- **Error detection**: Automatically detect and alert on command failures
- **Audit trail**: Track who runs which commands on which nodes
- **Resource usage**: Monitor job frequency and duration patterns
- **Proactive alerting**: Get notified of issues before manual checks

## Considerations

- **Resource overhead**: Each job now runs with an additional sidecar container
- **Log parsing**: Ensure execute-command.sh writes structured logs for proper parsing
- **Job completion**: Sidecar terminates when main container completes
- **Network policies**: Ensure metrics port (9090) is accessible to Prometheus

## Alternative Approaches

If sidecar approach adds too much overhead, consider:

1. **Centralized log aggregation**: Use Fluentd/Fluent Bit to collect logs
2. **Init container**: Parse logs after job completion
3. **External monitoring**: Poll job status via Kubernetes API
4. **Custom metrics exporter**: Dedicated service to monitor debugger namespace
