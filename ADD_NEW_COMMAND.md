# Adding a New Command to the Secure Debugger

This guide provides step-by-step instructions for adding a new command to the OpenShift Secure Debugger solution. We'll use `curl` as an example, but the same process applies to any command you want to add.

## Table of Contents

1. [Overview of Command Flow](#overview-of-command-flow)
2. [Step 1: Update the Wrapper Script](#step-1-update-the-wrapper-script)
3. [Step 2: Update the Execute Command Script](#step-2-update-the-execute-command-script)
4. [Step 3: Add Command Validation](#step-3-add-command-validation)
5. [Step 4: Implement Command Execution](#step-4-implement-command-execution)
6. [Step 5: Consider Security Implications](#step-5-consider-security-implications)
7. [Step 6: Test the New Command](#step-6-test-the-new-command)
8. [Troubleshooting](#troubleshooting)
9. [Command Implementation Checklist](#command-implementation-checklist)

## Overview of Command Flow

Before diving into changes, it's helpful to understand how commands flow through the system:

1. **User invokes `run-debugger-job.sh`** with command parameters
2. **Wrapper script validates** the command and creates a Kubernetes Job
3. **Job runs the `execute-command.sh` script** (from ConfigMap)
4. **Script validates and executes** the requested command
5. **Metrics are pushed** to Pushgateway for monitoring

## Step 1: Update the Wrapper Script

First, modify `scripts/run-debugger-job.sh` to recognize the new command:

### 1.1. Add to Allowed Commands List

```bash
# Find this line (around line 7):
ALLOWED_COMMANDS=(tcpdump ncat ip ifconfig netstat)

# Update it to include your new command:
ALLOWED_COMMANDS=(tcpdump ncat ip ifconfig netstat curl)
```

### 1.2. Add Command Examples to Help Text

Find the help text section (search for `cat <<EOF`) and add usage examples:

```bash
  curl:
    # Basic GET request
    $0 node1 mypod default curl https://example.com
    
    # POST request with data
    $0 node1 mypod default curl -X POST -d "key=value" https://example.com/api
    
    # With headers and timeout
    $0 node1 mypod default curl -H "Content-Type: application/json" --connect-timeout 10 https://example.com
```

## Step 2: Update the Execute Command Script

Next, modify the ConfigMap that contains the `execute-command.sh` script:

**File:** `k8s/execute-command-configmap.yaml`

## Step 3: Add Command Validation

Add validation logic for the new command. This prevents unsafe usage:

```bash
# Add a validation function for curl (around line 150)
validate_curl_args() {
    local args="$@"
    
    # Prevent dangerous options
    if echo "$args" | grep -E "(--connect-to|--output|-o|--upload-file|-T)" > /dev/null; then
        error "Dangerous curl options detected. File upload/download operations are not allowed"
        exit 1
    fi
    
    # Check for risky protocols or internal endpoints
    if echo "$args" | grep -E "(file://|ftp://|smb://|10\.|172\.16\.|192\.168\.|127\.0\.0\.1)" > /dev/null; then
        error "Accessing local files or internal networks directly is not allowed"
        exit 1
    fi
}

# Add to the validate_command function (around line 100)
validate_command() {
    local cmd="$1"
    if [[ "$cmd" != "tcpdump" && "$cmd" != "ncat" && "$cmd" != "ip" && "$cmd" != "ifconfig" && "$cmd" != "netstat" && "$cmd" != "curl" ]]; then
        error "Only 'tcpdump', 'ncat', 'ip', 'ifconfig', 'netstat', and 'curl' commands are allowed"
        echo "Usage: $0 <node-name> <pod-name> <pod-namespace> <command> [arguments...]"
        echo "Usage: $0 <node-name> - - <command> [arguments...]  # for node-level debugging"
        exit 1
    fi
    
    # If command is curl, validate its arguments
    if [[ "$cmd" == "curl" ]]; then
        shift
        validate_curl_args "$@"
    fi
    # ... existing validation code ...
}
```

## Step 4: Implement Command Execution

Add the execution logic for the new command in the embedded script:

```bash
# Find the section that processes commands (around line 370)
# Inside the embedded script portion

# Add this section for curl command handling
elif [[ "$COMMAND" == "curl" ]]; then
    if [[ -n "$nsenter_parameters" ]]; then
        echo "Running curl in pod network namespace..."
        echo "[DEBUG] About to run: nsenter $nsenter_parameters -- curl $ARGS" >&2
        nsenter $nsenter_parameters -- curl $ARGS
    else
        echo "Running curl in host network namespace..."
        echo "[DEBUG] About to run: curl $ARGS" >&2
        curl $ARGS
    fi
```

## Step 5: Consider Security Implications

Before implementing, evaluate security considerations:

1. **Container Image Requirements**: Ensure the container image has the command installed
2. **Permissions**: Consider if additional RBAC or capabilities are needed
3. **Network Access**: Determine if special network permissions are required
4. **Data Handling**: Think about where output will be stored/displayed
5. **Validation**: Implement strict validation to prevent abuse

### Example: Container Image Check

To verify curl is available in the container image:

```bash
# Check if the image already has curl installed
oc run curl-test --image=registry.redhat.io/openshift4/ose-tools-rhel8:latest \
  --rm -it --restart=Never -- which curl

# If not available, choose a different base image or add it to your custom image
```

## Step 6: Test the New Command

Always test the command thoroughly:

```bash
# Test in interactive mode
./scripts/run-debugger-job.sh

# Test with direct command
./scripts/run-debugger-job.sh worker-node-1 app-pod-name app-namespace curl https://kubernetes.io

# Test with invalid options (should be rejected)
./scripts/run-debugger-job.sh worker-node-1 app-pod-name app-namespace curl -o /tmp/file https://example.com
```

## Troubleshooting

If your new command doesn't work as expected:

1. **Check the job logs**:
   ```bash
   oc logs $(oc get pods -l job-name=debugger-job-* -n debugger --sort-by=.metadata.creationTimestamp -o name | tail -1) -n debugger
   ```

2. **Verify the command exists in the container**:
   ```bash
   oc exec $(oc get pods -l job-name=debugger-job-* -n debugger --sort-by=.metadata.creationTimestamp -o name | tail -1) -n debugger -- which curl
   ```

3. **Test command directly in a debug pod**:
   ```bash
   oc debug node/worker-node-1 -- chroot /host curl https://example.com
   ```

## Command Implementation Checklist

Use this checklist to ensure you've covered everything:

- [ ] Added command to `ALLOWED_COMMANDS` array
- [ ] Updated help text with good examples
- [ ] Added validation function for the command
- [ ] Implemented command execution logic
- [ ] Added appropriate timeouts
- [ ] Considered security implications
- [ ] Ensured command exists in container image
- [ ] Verified metrics are sent to Pushgateway
- [ ] Tested with various arguments and scenarios
- [ ] Updated documentation (if necessary)

---

**Example PR Description Template:**

```
Add support for curl command to debugger

This PR adds support for the curl command in the secure debugger tool:

- Added curl to the list of allowed commands
- Implemented validation to prevent dangerous options
- Added execution logic in pod or host network namespace
- Updated help text with usage examples
- Tested in both interactive and command-line modes

Security considerations:
- Blocked file upload/download options
- Prevented access to internal networks
- Limited to HTTP/HTTPS protocols
```
