#!/bin/bash

# setup-monitoring.sh - Setup monitoring and alerting for the debugger solution
# Usage: ./setup-monitoring.sh

set -e

# Configuration
NAMESPACE="fttc-ancillary"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITORING_DIR="$SCRIPT_DIR/../monitoring"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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
    log "Checking prerequisites..."
    
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
    
    # Check if namespace exists
    if ! oc get namespace "$NAMESPACE" &> /dev/null; then
        error "Namespace '$NAMESPACE' does not exist"
        exit 1
    fi
    
    log "Prerequisites check passed"
}

# Function to setup Prometheus monitoring
setup_prometheus() {
    log "Setting up Prometheus monitoring..."
    
    # Check if Prometheus Operator is available
    if oc get crd servicemonitors.monitoring.coreos.com &> /dev/null; then
        log "Prometheus Operator detected, installing ServiceMonitor and PrometheusRule..."
        oc apply -f "$MONITORING_DIR/prometheus-rules.yaml" -n "$NAMESPACE"
        info "Prometheus monitoring configured"
    else
        warn "Prometheus Operator not found, skipping Prometheus configuration"
        warn "To enable Prometheus monitoring, install the Prometheus Operator first"
    fi
}

# Function to setup logging
setup_logging() {
    log "Setting up audit logging configuration..."
    
    # Install logging config
    oc apply -f "$MONITORING_DIR/logging-config.yaml" -n "$NAMESPACE"
    
    # Create log directory on nodes (via DaemonSet)
    cat <<EOF | oc apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: setup-log-dirs-$(date +%s)
  namespace: $NAMESPACE
spec:
  template:
    spec:
      hostNetwork: true
      containers:
      - name: setup
        image: registry.redhat.io/ubi8/ubi:latest
        command: ["/bin/bash", "-c"]
        args:
        - |
          mkdir -p /host/var/log/debugger
          chmod 755 /host/var/log/debugger
          echo "Log directory setup complete"
        volumeMounts:
        - name: host-var
          mountPath: /host/var
        securityContext:
          privileged: true
      volumes:
      - name: host-var
        hostPath:
          path: /var
      restartPolicy: Never
      tolerations:
      - operator: Exists
EOF
    
    info "Logging configuration installed"
}

# Function to setup alerting
setup_alerting() {
    log "Setting up alerting configuration..."
    
    # Create alerting configmap
    cat <<EOF | oc apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: debugger-alert-config
  namespace: $NAMESPACE
data:
  alert-config.env: |
    # Email configuration
    ALERT_EMAIL=${ALERT_EMAIL:-}
    
    # Slack configuration  
    SLACK_WEBHOOK_URL=${SLACK_WEBHOOK_URL:-}
    
    # Syslog configuration
    SYSLOG_SERVER=${SYSLOG_SERVER:-localhost}
    SYSLOG_PORT=${SYSLOG_PORT:-514}
    
    # Log forwarding
    LOG_FORWARDING_HOST=${LOG_FORWARDING_HOST:-}
    LOG_FORWARDING_PORT=${LOG_FORWARDING_PORT:-24224}
EOF
    
    info "Alerting configuration created"
    
    echo ""
    info "=== Alerting Configuration ==="
    echo "To enable email alerts, set ALERT_EMAIL environment variable:"
    echo "  export ALERT_EMAIL=security@example.com"
    echo ""
    echo "To enable Slack alerts, set SLACK_WEBHOOK_URL:"
    echo "  export SLACK_WEBHOOK_URL=https://hooks.slack.com/services/..."
    echo ""
    echo "Then re-run this script to update the configuration."
}

# Function to test monitoring
test_monitoring() {
    log "Testing monitoring setup..."
    
    # Check if daemon pods are running
    local pods=$(oc get pods -l app=debugger-daemon -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}')
    
    if [[ -z "$pods" ]]; then
        error "No debugger daemon pods found"
        return 1
    fi
    
    # Test audit logging
    log "Testing audit log functionality..."
    
    for pod in $pods; do
        local node=$(oc get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.nodeName}')
        echo "Checking logs from pod $pod on node $node..."
        
        # Look for recent audit entries
        if oc logs "$pod" -n "$NAMESPACE" --tail=10 | grep -q "Starting debugger daemon"; then
            info "✓ Pod $pod is logging correctly"
        else
            warn "⚠ Pod $pod may not be logging properly"
        fi
    done
    
    info "Monitoring test completed"
}

# Function to show status
show_status() {
    log "Monitoring and Alerting Status:"
    echo ""
    
    # Check Prometheus resources
    if oc get servicemonitor debugger-audit-monitor -n "$NAMESPACE" &> /dev/null; then
        echo "✓ ServiceMonitor: debugger-audit-monitor"
    else
        echo "✗ ServiceMonitor: NOT FOUND"
    fi
    
    if oc get prometheusrule debugger-alerts -n "$NAMESPACE" &> /dev/null; then
        echo "✓ PrometheusRule: debugger-alerts"
    else
        echo "✗ PrometheusRule: NOT FOUND"
    fi
    
    # Check logging resources
    if oc get configmap debugger-fluentd-config -n "$NAMESPACE" &> /dev/null; then
        echo "✓ Logging ConfigMap: debugger-fluentd-config"
    else
        echo "✗ Logging ConfigMap: NOT FOUND"
    fi
    
    if oc get configmap debugger-alert-config -n "$NAMESPACE" &> /dev/null; then
        echo "✓ Alert ConfigMap: debugger-alert-config"
    else
        echo "✗ Alert ConfigMap: NOT FOUND"
    fi
    
    echo ""
    info "Use './audit-viewer.sh follow' to monitor live audit logs"
    info "Use './audit-viewer.sh violations' to check for security violations"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --prometheus    Setup Prometheus monitoring only"
    echo "  --logging       Setup logging configuration only"
    echo "  --alerting      Setup alerting configuration only"
    echo "  --test          Test monitoring setup"
    echo "  --status        Show monitoring status"
    echo "  --help          Show this help message"
    echo ""
    echo "Environment variables for alerting:"
    echo "  ALERT_EMAIL             Email address for security alerts"
    echo "  SLACK_WEBHOOK_URL       Slack webhook URL for notifications"
    echo "  LOG_FORWARDING_HOST     Host for log forwarding"
    echo "  LOG_FORWARDING_PORT     Port for log forwarding (default: 24224)"
}

# Main function
main() {
    case "${1:-all}" in
        --prometheus)
            check_prerequisites
            setup_prometheus
            ;;
        --logging)
            check_prerequisites
            setup_logging
            ;;
        --alerting)
            check_prerequisites
            setup_alerting
            ;;
        --test)
            check_prerequisites
            test_monitoring
            ;;
        --status)
            check_prerequisites
            show_status
            ;;
        --help|-h)
            show_usage
            exit 0
            ;;
        all|"")
            check_prerequisites
            setup_prometheus
            setup_logging
            setup_alerting
            test_monitoring
            show_status
            ;;
        *)
            error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
    
    log "Monitoring setup completed!"
}

# Run main function
main "$@"