# Pushgateway Integration for Debugger Tool

This document explains how the debugger tool integrates with Prometheus Pushgateway to enable alerts from debugging operations to flow to Prometheus and ServiceNow.

## Table of Contents

- [Pushgateway Integration for Debugger Tool](#pushgateway-integration-for-debugger-tool)
  - [Table of Contents](#table-of-contents)
  - [Overview](#overview)
  - [Pushgateway Deployment](#pushgateway-deployment)
    - [What is Pushgateway?](#what-is-pushgateway)
    - [Where to Deploy Pushgateway](#where-to-deploy-pushgateway)
    - [Deployment Steps](#deployment-steps)
  - [Component Communication Flow](#component-communication-flow)
    - [Component Interaction Details](#component-interaction-details)
  - [How Debugger Tool Sends Alerts](#how-debugger-tool-sends-alerts)
  - [Alert Flow to ServiceNow](#alert-flow-to-servicenow)
    - [Alert Rules](#alert-rules)
    - [ServiceNow Integration](#servicenow-integration)
  - [Troubleshooting](#troubleshooting)
    - [Common Issues](#common-issues)
    - [Diagnostic Commands](#diagnostic-commands)

## Overview

The debugger tool integrates with Prometheus monitoring through Pushgateway to track debugging operations and send alerts for certain events (e.g., extensive tcpdump sessions, failed debugging attempts). This monitoring integration enables:

- Recording of all debugging operations for audit purposes
- Alerting on potentially suspicious or problematic debugging activity
- Integration with ServiceNow for ticket creation and tracking
- Visibility into cluster debugging operations for administrators

## Pushgateway Deployment

### What is Pushgateway?

Prometheus Pushgateway is a component that allows ephemeral and batch jobs to expose their metrics to Prometheus. Since our debugger jobs are short-lived, Pushgateway serves as an intermediary that accepts metrics from the debugger jobs and holds them for Prometheus to scrape.

### Where to Deploy Pushgateway

Pushgateway should be deployed in the same namespace as the debugger tool (`debugger` namespace) for simplicity and security isolation.

### Deployment Steps

To deploy Pushgateway, use the existing manifest available in the repository:

```bash
# Apply the Pushgateway deployment manifest
oc apply -f scripts/pushgateway.yaml
```

The Pushgateway deployment file (`scripts/pushgateway.yaml`) includes:
- Pushgateway Deployment
- Service to expose Pushgateway
- ServiceMonitor for Prometheus to scrape Pushgateway
- PrometheusRule with alert definitions

## Component Communication Flow

```
┌───────────────────┐     Push Metrics     ┌───────────────────┐     Scrape      ┌───────────────────┐
│                   │                      │                   │                  │                   │
│   Debugger Job    │────────────────────▶│    Pushgateway    │◀────────────────│    Prometheus     │
│  run-debugger-job │                      │                   │                  │                   │
│                   │                      │                   │                  │                   │
└───────────────────┘                      └───────────────────┘                  └─────────┬─────────┘
         │                                                                                  │
         │                                                                                  │
         │                                                                                  │
         │                                                                                  │ Fire Alerts
         │                                                                                  │
         │         ┌───────────────────┐                                          ┌─────────▼─────────┐
         │         │                   │          Create Tickets                  │                   │
         │         │    ServiceNow     │◀─────────────────────────────────────────│   AlertManager    │
         └────────▶│    (Incidents)    │                                          │                   │
    Job status     │                   │                                          │                   │
    information    └───────────────────┘                                          └───────────────────┘
```

### Component Interaction Details

1. **Debugger Job to Pushgateway**:
   - The `run-debugger-job.sh` script creates a Kubernetes job to run debugging commands
   - The job pod runs `execute-command.sh` which executes the debug command and pushes metrics to Pushgateway
   - Metrics include job status, execution details, and command-specific data (e.g., tcpdump duration)

2. **Pushgateway to Prometheus**:
   - Pushgateway stores the metrics pushed by debugger jobs
   - Prometheus discovers Pushgateway through the ServiceMonitor configuration
   - Prometheus regularly scrapes metrics from Pushgateway (typically every 15-30 seconds)
   - Prometheus evaluates alert rules against the metrics data

3. **Prometheus to AlertManager**:
   - When alert conditions are met (e.g., long-running jobs, failed jobs), Prometheus fires alerts
   - These alerts are sent to AlertManager
   - AlertManager groups, deduplicates, and routes alerts based on its configuration

4. **AlertManager to ServiceNow**:
      - AlertManager has a webhook receiver configured for ServiceNow
   - Alerts are formatted as ServiceNow incidents and sent to the ServiceNow API
   - The mock ServiceNow service in the debugger namespace receives these alerts

5. **Direct Job Information to ServiceNow**:
   - For critical events, the debugger job can also send information directly to ServiceNow
   - This provides immediate notification without waiting for the Prometheus scrape cycle

## How Debugger Tool Sends Alerts

The `run-debugger-job.sh` script (along with `execute-command.sh`) integrates with Pushgateway to send metrics about debugging operations. Here's how it works:

1. When a debugging job is executed, the script captures metadata including:
   - User who initiated the debugging
   - Target node and pod
   - Command being executed
   - Timestamp
   - Job name and other contextual information

2. The `execute-command.sh` script (stored in a ConfigMap and mounted into debugging pods) includes the `push_metric` function, which formats this data as Prometheus metrics and pushes them to the Pushgateway service.

3. Different metric types are pushed at various stages of job execution:
   - `debugger_job_started_total`: When a debugging job starts
   - `debugger_job_completed_total`: When a job completes successfully
   - `debugger_job_failed_total`: When a job fails
   - `debugger_job_status`: Status indicator (1=success, 0=running, -1=failed)
   - `debugger_job_duration_seconds`: Duration of job execution
   - `debugger_pcap_files_generated_total`: Number of PCAP files generated (for tcpdump jobs)

## Alert Flow to ServiceNow

The flow from debugger tool to ServiceNow follows these steps:

1. **Debugger Job → Pushgateway**: Metrics are pushed from debugger jobs to Pushgateway
2. **Pushgateway → Prometheus**: Prometheus scrapes metrics from Pushgateway using the ServiceMonitor
3. **Prometheus → AlertManager**: AlertManager evaluates rules defined in PrometheusRules and generates alerts
4. **AlertManager → ServiceNow**: AlertManager sends alerts to ServiceNow via webhook

### Alert Rules

The `pushgateway.yaml` file already includes alert rules for the debugger tool, such as:
- `DebuggerJobCreated`: Notifies when a debugging job starts
- `DebuggerJobCompleted`: Notifies when a job completes successfully
- `DebuggerJobFailed`: Notifies when a job fails
- `DebuggerJobLongRunning`: Alerts on jobs running longer than expected
- `DebuggerPcapGenerated`: Tracks PCAP file generation
- `DebuggerTcpdumpNoPcap`: Alerts when tcpdump jobs don't generate expected files

### ServiceNow Integration

The AlertManager is configured to send alerts to a  ServiceNow instance already.

## Troubleshooting

### Common Issues

1. **Metrics not showing in Pushgateway**:
   - Check network connectivity from debug pod to Pushgateway
   - Verify the Pushgateway service DNS is correct
   - Check for errors in the debug job logs

2. **Pushgateway reachable but no alerts**:
   - Verify Prometheus is scraping Pushgateway
   - Check alert rule syntax
   - Ensure alert thresholds match your expectations

3. **Alerts firing but no ServiceNow tickets**:
   - Check AlertManager configuration
   - Verify webhook URL and credentials
   - Look for errors in AlertManager logs

### Diagnostic Commands

```bash
# Check Pushgateway logs
oc logs deployment/pushgateway -n debugger

# Check if metrics exist in Pushgateway
oc exec $(oc get pod -l app=pushgateway -n debugger -o name | head -1) -n debugger -- curl http://localhost:9091/metrics | grep debugger_

# Test direct push to Pushgateway
oc exec $(oc get pod -l app=pushgateway -n debugger -o name | head -1) -n debugger -- sh -c "echo 'test_metric 1' | curl --data-binary @- http://localhost:9091/metrics/job/test"

```
