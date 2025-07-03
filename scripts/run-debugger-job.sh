#!/bin/bash
# run-debugger-job.sh - Wrapper to launch execute-command.sh in a Job in the debugger namespace with elevated permissions
# Usage: ./run-debugger-job.sh <node-name> <pod-name> <pod-namespace> <command> [arguments...]

set -e

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    cat <<EOF
Usage: $0 <node-name> <pod-name> <pod-namespace> <command> [arguments...]
Or run with no arguments for interactive mode.

Available commands and examples:

  tcpdump:
    # Capture all traffic on all interfaces for 30 seconds
    $0 node1 mypod default tcpdump 30
    # Capture traffic on eth0 with a filter for port 80 for 60 seconds
    $0 node1 mypod default tcpdump -i eth0 port 80 60

  ncat:
    # Listen on port 12345
    $0 node1 mypod default ncat -l 12345
    # Connect to 10.0.0.2:80
    $0 node1 mypod default ncat 10.0.0.2 80

  ip:
    # Show all interfaces
    $0 node1 mypod default ip a
    # Show routing table
    $0 node1 mypod default ip route

  ifconfig:
    # Show all interfaces
    $0 node1 mypod default ifconfig

Interactive mode:
  Just run $0 and you will be prompted for all required values.
EOF
    exit 0
fi

if [[ $# -lt 4 ]]; then
    echo "Interactive mode: Please enter required parameters."
    read -rp "which node: " NODE_NAME
    read -rp "Pod name: " POD_NAME
    read -rp "Pod namespace: " POD_NAMESPACE
    read -rp "Command (tcpdump/ncat/ip/ifconfig): " COMMAND
    read -rp "Arguments (space-separated, leave blank if none): " ARGS_INPUT
    read -rp "Timeout (seconds): " TIMEOUT
    # Split ARGS_INPUT into array if not empty
    if [[ -n "$ARGS_INPUT" ]]; then
      # shellcheck disable=SC2206
      ARGS=($ARGS_INPUT)
    else
      ARGS=()
    fi
    ARGS+=("$TIMEOUT")
else
    NODE_NAME="$1"
    POD_NAME="$2"
    POD_NAMESPACE="$3"
    COMMAND="$4"
    shift 4
    ARGS=("$@")
fi

USER_NAME=$(whoami)
TIMESTAMP=$(date +%s)
JOB_NAME="debugger-job-$TIMESTAMP"
JOB_FILE="/tmp/$JOB_NAME.yaml"

# Build the args array for YAML (fix indentation and trailing whitespace)
ARGS_YAML=""
for arg in "$NODE_NAME" "$POD_NAME" "$POD_NAMESPACE" "$COMMAND" "${ARGS[@]}"; do
  ARGS_YAML+="        - \"$arg\"\n"
done

# Remove trailing newline from ARGS_YAML to avoid YAML parse error
ARGS_YAML=$(echo -e "$ARGS_YAML" | sed '/^$/d')

cat > "$JOB_FILE" <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: $JOB_NAME
  namespace: debugger
  labels:
    app: debugger-job
    user: "$USER_NAME"
spec:
  ttlSecondsAfterFinished: 3600
  backoffLimit: 1
  template:
    metadata:
      labels:
        app: debugger-job
        user: "$USER_NAME"
    spec:
      serviceAccountName: debugger-sa
      imagePullSecrets:
      - name: pull-secret
      restartPolicy: Never
      hostNetwork: true
      hostPID: true
      securityContext:
        runAsUser: 0
      nodeSelector:
        kubernetes.io/hostname: "$NODE_NAME"
      containers:
      - name: debugger
        image: registry.redhat.io/rhel8/support-tools:8.10-15.1749683615
        command: ["/opt/scripts/execute-command.sh"]
        args:
$ARGS_YAML        
        securityContext:
          privileged: true
          capabilities:
            add:
            - NET_ADMIN
            - NET_RAW
            - SYS_ADMIN
            - SYS_PTRACE
        env:
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        - name: REMOTE_USER
          value: "$USER_NAME"
        volumeMounts:
        - name: execute-command-script
          mountPath: /opt/scripts/execute-command.sh
          subPath: execute-command.sh
          readOnly: true
        - name: host-proc
          mountPath: /host/proc
          readOnly: true
        - name: host-sys
          mountPath: /host/sys
          readOnly: true
        - name: host-dev
          mountPath: /host/dev
        - name: audit-logs
          mountPath: /var/log
        - name: host
          mountPath: /host
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
      volumes:
      - name: execute-command-script
        configMap:
          name: execute-command-script
          defaultMode: 0755
      - name: host-proc
        hostPath:
          path: /proc
      - name: host-sys
        hostPath:
          path: /sys
      - name: host-dev
        hostPath:
          path: /dev
      - name: host
        hostPath:
          path: /
      - name: audit-logs
        hostPath:
          path: /var/log/debugger
          type: DirectoryOrCreate
EOF

echo "\n===== GENERATED JOB YAML ====="
cat "$JOB_FILE"
echo "===== END JOB YAML =====\n"

echo "Launching job in debugger namespace..."
kubectl apply -f "$JOB_FILE"
echo "Job launched. Waiting for job to be scheduled..."

# Wait for the job to be scheduled and check for admission errors (e.g., Gatekeeper denial)
for i in {1..30}; do
  JOB_STATUS=$(kubectl get job "$JOB_NAME" -n debugger -o json 2>/dev/null || true)
  if [[ -n "$JOB_STATUS" ]]; then
    # Check if the job has any warning events for admission webhook denials
    ADMISSION_ERROR_MSG=$(kubectl get events -n debugger --field-selector involvedObject.name=$JOB_NAME,type=Warning -o jsonpath='{.items[*].message}' | grep -o 'Error creating: admission webhook "validation.gatekeeper.sh" denied the.*' || true)
    if [[ -n "$ADMISSION_ERROR_MSG" ]]; then
      echo "Admission webhook denied the job: $ADMISSION_ERROR_MSG"
      echo "Deleting failed job $JOB_NAME ..."
      kubectl delete job "$JOB_NAME" -n debugger --ignore-not-found
      exit 1
    fi
    # If pods are created, break and continue
    POD_NAME=$(kubectl get pods -n debugger -l job-name=$JOB_NAME -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    if [[ -n "$POD_NAME" ]]; then
      break
    fi
  fi
  sleep 2
done

# Wait for the pod to be created, but if not, check for warning events on the job
POD_NAME=""
for i in {1..30}; do
  POD_NAME=$(kubectl get pods -n debugger -l job-name=$JOB_NAME -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  if [[ -n "$POD_NAME" ]]; then
    break
  fi
  sleep 2
done


echo "Streaming logs for pod: $POD_NAME"
# Stream logs for up to 90 seconds, then continue regardless
timeout 90s kubectl logs -f "$POD_NAME" -n debugger || true

# Wait for job completion
kubectl wait --for=condition=complete --timeout=600s job/$JOB_NAME -n debugger || {
  echo "Job did not complete successfully.";
  exit 1;
}
echo "Job completed."

# Create a new pod to copy files from the hostPath after job completion
COPY_POD_NAME="copy-pcap-$JOB_NAME"
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: $COPY_POD_NAME
  namespace: debugger
spec:
  serviceAccountName: debugger-sa
  restartPolicy: Never
  nodeSelector:
    kubernetes.io/hostname: "$NODE_NAME"
  containers:
  - name: copy
    image: registry.redhat.io/rhel8/support-tools:8.10-15.1749683615
    command: ["sleep", "3600"]
    securityContext:
      privileged: true
    volumeMounts:
    - name: host
      mountPath: /host
  volumes:
    - name: host
      hostPath:
        path: /
EOF

# Wait for the copy pod to be running
for i in {1..30}; do
  PHASE=$(kubectl get pod $COPY_POD_NAME -n debugger -o jsonpath='{.status.phase}' 2>/dev/null || true)
  if [[ "$PHASE" == "Running" ]]; then
    break
  fi
  sleep 2
done



LOCAL_PCAP_DIR="./pcap-dump-$JOB_NAME"
mkdir -p "$LOCAL_PCAP_DIR"

# Extract the pcap filename from the debug pod logs
PCAP_FILE=$(kubectl logs "$POD_NAME" -n debugger | grep 'Output will be saved to:' | awk -F': ' '{print $2}' | tail -1)
if [[ -z "$PCAP_FILE" ]]; then
  echo "Could not determine pcap file name from pod logs. Copying all .pcap files."
  kubectl cp "debugger/$COPY_POD_NAME:/host/var/tmp/." "$LOCAL_PCAP_DIR" || echo "No pcap files found or copy failed."
else
  echo "Copying pcap file $PCAP_FILE from pod $COPY_POD_NAME to $LOCAL_PCAP_DIR ..."
  kubectl cp "debugger/$COPY_POD_NAME:$PCAP_FILE" "$LOCAL_PCAP_DIR/tcpdump.pcap" || echo "PCAP file not found or copy failed."
fi
echo "PCAP files (if any) are now in $LOCAL_PCAP_DIR"

# Clean up the copy pod
echo "Deleting copy pod $COPY_POD_NAME ..."
kubectl delete pod $COPY_POD_NAME -n debugger --ignore-not-found
