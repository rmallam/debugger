#!/bin/bash
# run-debugger-job.sh - Wrapper to launch execute-command.sh in a Job in the debugger namespace with elevated permissions
# Usage: ./run-debugger-job.sh <node-name> <pod-name> <pod-namespace> <command> [arguments...]


set -e

# --- Input validation ---
ALLOWED_COMMANDS=(tcpdump ncat ip ifconfig netstat)

# If at least 4 arguments are provided, validate command and namespace
if [[ $# -ge 4 ]]; then
    INPUT_NAMESPACE="$3"
    INPUT_COMMAND="$4"

    # Validate command
    VALID_CMD=false
    for cmd in "${ALLOWED_COMMANDS[@]}"; do
        if [[ "$INPUT_COMMAND" == "$cmd" ]]; then
            VALID_CMD=true
            break
        fi
    done
    if [[ "$VALID_CMD" != true ]]; then
        echo "[ERROR] Invalid command: $INPUT_COMMAND"
        echo "Allowed commands are: ${ALLOWED_COMMANDS[*]}"
        exit 1
    fi

    # Validate namespace exists
    if ! oc get namespace "$INPUT_NAMESPACE" >/dev/null 2>&1; then
        echo "[ERROR] Namespace '$INPUT_NAMESPACE' does not exist."
        exit 1
    fi
fi

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
    # If no timeout is specified, a default of 30 seconds will be used

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

  netstat:
    # Show all netstat
    $0 node1 mypod default netstat

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

    # Validate namespace exists
    if ! oc get namespace "$POD_NAMESPACE" >/dev/null 2>&1; then
        echo "[ERROR] Namespace '$POD_NAMESPACE' does not exist."
        exit 1
    fi

    # Command validation loop
    while true; do
      read -rp "Command (tcpdump/ncat/ip/ifconfig/netstat): " COMMAND
      VALID_CMD=false
      for cmd in "${ALLOWED_COMMANDS[@]}"; do
        if [[ "$COMMAND" == "$cmd" ]]; then
          VALID_CMD=true
          break
        fi
      done
      if [[ "$VALID_CMD" == true ]]; then
        break
      else
        echo "[ERROR] Invalid command: $COMMAND"
        echo "Allowed commands are: ${ALLOWED_COMMANDS[*]}"
      fi
    done

    read -rp "Arguments (space-separated, leave blank if none): " ARGS_INPUT
    read -rp "Timeout (seconds, default: 30): " TIMEOUT
    # Split ARGS_INPUT into array if not empty
    if [[ -n "$ARGS_INPUT" ]]; then
      # shellcheck disable=SC2206
      ARGS=($ARGS_INPUT)
    else
      ARGS=()
    fi
    
    # If timeout is empty or not a number, use default of 30 seconds
    if [[ -z "$TIMEOUT" || ! "$TIMEOUT" =~ ^[0-9]+$ ]]; then
      echo "Using default timeout of 30 seconds"
      TIMEOUT="30"
    fi
    ARGS+=("$TIMEOUT")
else
    NODE_NAME="$1"
    POD_NAME="$2"
    POD_NAMESPACE="$3"
    COMMAND="$4"
    shift 4
    ARGS=("$@")
    # If command is tcpdump and no timeout is present, add default 30
    if [[ "$COMMAND" == "tcpdump" ]]; then
      # Only add default if ARGS is not empty and last arg is not a number (portable array subscript)
      if (( ${#ARGS[@]} == 0 )) || [[ ! "${ARGS[@]: -1}" =~ ^[0-9]+$ ]]; then
        echo "Using default timeout of 30 seconds for tcpdump"
        ARGS+=("30")
      fi
    # For other commands, add default timeout if needed
    elif [[ "$COMMAND" == "ncat" || "$COMMAND" == "ip" || "$COMMAND" == "ifconfig" || "$COMMAND" == "netstat" ]]; then
      # Check if the last argument is a number, if not add default timeout
      if (( ${#ARGS[@]} == 0 )) || [[ ! "${ARGS[@]: -1}" =~ ^[0-9]+$ ]]; then
        echo "Using default timeout of 30 seconds"
        ARGS+=("30")
      fi
    fi
fi

USER_NAME=$(whoami | cut -d'\' -f2)
TIMESTAMP=$(date +%s)
JOB_NAME="debugger-job-$TIMESTAMP"
JOB_FILE="/tmp/$JOB_NAME.yaml"

# Note: Pushgateway IP will be determined inside the container for better timing accuracy

# Log the exact execution details
echo "============================================="
echo "DEBUGGER JOB EXECUTION LOG"
echo "============================================="
echo "Timestamp: $(date +'%Y-%m-%d %H:%M:%S %Z')"
echo "User: $USER_NAME"
echo "Job Name: $JOB_NAME"
echo "Target Node: $NODE_NAME"
echo "Target Pod: $POD_NAME (namespace: $POD_NAMESPACE)"
echo "Command: $COMMAND"
echo "Arguments: ${ARGS[*]}"
echo "Kubernetes Context: $(oc config current-context 2>/dev/null || echo 'unknown')"
echo "Debugger Namespace: debugger"
echo "Service Account: debugger-sa"
echo "Container Image: registry.redhat.io/openshift4/ose-tools-rhel8:latest"
echo "Security Context: privileged=true, hostNetwork=true, hostPID=true"
echo "Capabilities: NET_ADMIN, NET_RAW, SYS_ADMIN, SYS_PTRACE"
echo "============================================="

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
        - name: redhat-debugger-pull-secret
      restartPolicy: Never
      hostNetwork: true
      hostPID: true
      securityContext:
        runAsUser: 0
      nodeSelector:
        kubernetes.io/hostname: "$NODE_NAME"
      containers:
      - name: debugger
        image: registry.redhat.io/openshift4/ose-tools-rhel8:latest
        command: ["/bin/bash"]
        args: 
        - "/opt/scripts/execute-command.sh"
        - "$NODE_NAME"
        - "$POD_NAME"
        - "$POD_NAMESPACE"
        - "$COMMAND"
        - "${ARGS[@]}"
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
        - name: JOB_NAME
          value: "$JOB_NAME"
        - name: COMMAND
          value: "$COMMAND"
        - name: POD_NAME
          value: "$POD_NAME"
        - name: POD_NAMESPACE
          value: "$POD_NAMESPACE"
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

# echo "\n===== GENERATED JOB YAML ====="
# cat "$JOB_FILE"
# echo "===== END JOB YAML =====\n"

echo "============================================="
echo "KUBERNETES COMMAND EXECUTION"
echo "============================================="
echo "About to execute: oc apply -f $JOB_FILE"
echo "Job will run on node: $NODE_NAME"
echo "Job will execute: debugger-script.sh with command $COMMAND ${ARGS[*]}"
echo "============================================="

echo "Launching job in debugger namespace..."
oc apply -f "$JOB_FILE"
echo "Job launched. Waiting for job to be scheduled..."

# Wait for the job to be scheduled and check for admission errors (e.g., Gatekeeper denial)
for i in {1..30}; do
  JOB_STATUS=$(oc get job "$JOB_NAME" -n debugger -o json 2>/dev/null || true)
  if [[ -n "$JOB_STATUS" ]]; then
    # Check if the job has any warning events for admission webhook denials
    ADMISSION_ERROR_MSG=$(oc get events -n debugger --field-selector involvedObject.name=$JOB_NAME,type=Warning -o jsonpath='{.items[*].message}' | grep -o 'Error creating: admission webhook "validation.gatekeeper.sh" denied the.*' || true)
    if [[ -n "$ADMISSION_ERROR_MSG" ]]; then
      echo "Admission webhook denied the job: $ADMISSION_ERROR_MSG"
      echo "Deleting failed job $JOB_NAME ..."
      oc delete job "$JOB_NAME" -n debugger --ignore-not-found
      exit 1
    fi
    # If pods are created, break and continue
    POD_NAME=$(oc get pods -n debugger -l job-name=$JOB_NAME -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    if [[ -n "$POD_NAME" ]]; then
      break
    fi
  fi
  sleep 2
done

# Wait for the pod to be created, but if not, check for warning events on the job
POD_NAME=""
for i in {1..30}; do
  POD_NAME=$(oc get pods -n debugger -l job-name=$JOB_NAME -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  if [[ -n "$POD_NAME" ]]; then
    break
  fi
  sleep 2
done

# Wait for the pod to be in Running state, and check for image pull failures
echo "Waiting for pod $POD_NAME to be ready..."
for i in {1..60}; do
  POD_PHASE=$(oc get pod "$POD_NAME" -n debugger -o jsonpath='{.status.phase}' 2>/dev/null || true)
  CONTAINER_STATUS=$(oc get pod "$POD_NAME" -n debugger -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}' 2>/dev/null || true)

  if [[ "$POD_PHASE" == "Running" || "$POD_PHASE" == "Succeeded" ]]; then
    echo "Pod $POD_NAME is now $POD_PHASE"
    break
  fi

  if [[ "$CONTAINER_STATUS" == "ImagePullBackOff" || "$CONTAINER_STATUS" == "ErrImagePull" ]]; then
    echo "[ERROR] Pod $POD_NAME failed to pull image: $CONTAINER_STATUS"
    echo "Pod description:"
    oc describe pod "$POD_NAME" -n debugger
    echo "Deleting failed job $JOB_NAME ..."
    oc delete job "$JOB_NAME" -n debugger --ignore-not-found
    exit 1
  fi

  if [[ "$CONTAINER_STATUS" == "ContainerCreating" || "$POD_PHASE" == "Pending" ]]; then
    echo "Pod $POD_NAME is still $POD_PHASE ($CONTAINER_STATUS). Waiting..."
  fi

  if [[ "$CONTAINER_STATUS" == "failed"  ]]; then
    echo "Pod $POD_NAME failed to startup. ..."
    oc logs "$POD_NAME" -n debugger
  fi

  sleep 3
done

if [[ "$POD_PHASE" != "Running" && "$POD_PHASE" != "Succeeded" ]]; then
  echo "[ERROR] Pod $POD_NAME did not reach Running state in time. Current phase: $POD_PHASE"
  echo "Pod description:"
  oc describe pod "$POD_NAME" -n debugger
  echo "Deleting failed job $JOB_NAME ..."
  oc delete job "$JOB_NAME" -n debugger --ignore-not-found
  exit 1
fi




echo "Streaming logs for pod: $POD_NAME"
echo "============================================="
echo "POD EXECUTION DETAILS"
echo "============================================="
echo "Pod Name: $POD_NAME"
echo "Job Name: $JOB_NAME"
echo "Namespace: debugger"
echo "Node: $NODE_NAME"
echo "Getting pod logs with: oc logs -f $POD_NAME -n debugger"
echo "============================================="

# Stream logs for up to 90 seconds, then continue regardless
timeout 90s oc logs -f "$POD_NAME" -n debugger || true

# Wait for job completion
oc wait --for=condition=complete --timeout=600s job/$JOB_NAME -n debugger || {
  echo "Job did not complete successfully.";
  exit 1;
}
echo "Job completed."

# Only run copy pcap pod logic for tcpdump command
if [[ "$COMMAND" == "tcpdump" ]]; then
  # Create a new pod to copy files from the hostPath after job completion, but before deleting the debug job/pod
  COPY_POD_NAME="copy-pcap-$JOB_NAME"
  cat <<EOF | oc apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: $COPY_POD_NAME
  namespace: debugger
spec:
  serviceAccountName: debugger-sa
  imagePullSecrets:
    - name: redhat-debugger-pull-secret
  restartPolicy: Never
  nodeSelector:
    kubernetes.io/hostname: "$NODE_NAME"
  containers:
  - name: copy
    image: registry.redhat.io/openshift4/ose-tools-rhel8:latest
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
    PHASE=$(oc get pod $COPY_POD_NAME -n debugger -o jsonpath='{.status.phase}' 2>/dev/null || true)
    if [[ "$PHASE" == "Running" ]]; then
      break
    fi
    sleep 2
  done

  LOCAL_PCAP_DIR="./pcap-dump-$JOB_NAME"
  mkdir -p "$LOCAL_PCAP_DIR"

  # Extract the pcap filename from the debug pod logs
  PCAP_FILE=$(oc logs "$POD_NAME" -n debugger | grep 'Output will be saved to:' | awk -F': ' '{print $2}' | tail -1)

  echo "============================================="
  echo "FILE COPY OPERATION"
  echo "============================================="
  echo "Copy Pod: $COPY_POD_NAME"
  echo "Source Node: $NODE_NAME" 
  echo "Local Directory: $LOCAL_PCAP_DIR"

  if [[ -z "$PCAP_FILE" ]]; then
    echo "Could not determine pcap file name from pod logs. Copying all .pcap files."
    echo "Copy command: oc cp debugger/$COPY_POD_NAME:/host/var/tmp/. $LOCAL_PCAP_DIR"
    oc cp "debugger/$COPY_POD_NAME:/host/var/tmp/." "$LOCAL_PCAP_DIR" || echo "No pcap files found or copy failed."
  else
    # Ensure PCAP_FILE is an absolute path, else prepend /host if needed
    if [[ "$PCAP_FILE" != /* ]]; then
      PCAP_FILE="/host$PCAP_FILE"
    fi
    echo "Copying pcap file $PCAP_FILE from pod $COPY_POD_NAME to $LOCAL_PCAP_DIR ..."
    echo "Copy command: oc cp debugger/$COPY_POD_NAME:$PCAP_FILE $LOCAL_PCAP_DIR/tcpdump.pcap"
    oc cp "debugger/$COPY_POD_NAME:$PCAP_FILE" "$LOCAL_PCAP_DIR/tcpdump.pcap" || echo "PCAP file not found or copy failed."
  fi
  echo "============================================="
  echo "PCAP files (if any) are now in $LOCAL_PCAP_DIR"

  # Clean up the copy pod
  echo "Deleting copy pod $COPY_POD_NAME ..."
  oc delete pod $COPY_POD_NAME -n debugger --ignore-not-found
fi

# Clean up the debug job and pod
echo "Deleting job $JOB_NAME and associated pods..."
oc delete job "$JOB_NAME" -n debugger --ignore-not-found
echo "Cleanup complete."
