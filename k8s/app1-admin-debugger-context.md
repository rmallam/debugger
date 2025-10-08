# OpenShift Debugger Workflow: User Story and Context for app1-admin Service Account

## User Story

**As an application user (app1-admin Service Account in the app1 namespace), I need to be able to run advanced network debugging jobs (such as tcpdump, ncat, ip, ifconfig) on OpenShift nodes and pods, without being granted cluster-admin or privileged SCC access. I should be able to launch these jobs using the provided `run-debugger-job.sh` script, which creates a Kubernetes Job in the `debugger` namespace, using a secure and controlled workflow.**

---

## Workflow Overview

1. **The app user (app1-admin SA) runs the `run-debugger-job.sh` script.**
   - This script is designed to be used by application teams who do not have cluster-admin or privileged SCC access.
   - The script takes parameters such as node name, pod name, namespace, command (tcpdump/ncat/ip/ifconfig), and arguments (including capture duration for tcpdump).

2. **The script creates a Kubernetes Job in the `debugger` namespace.**
   - The Job uses a container image with network tools and mounts host paths for network namespace access.
   - The Job runs as the `debugger-sa` Service Account in the `debugger` namespace.
   - The Job references a ConfigMap (`execute-command-configmap.yaml`) that provides the main entrypoint script (`execute-command.sh`).

3. **The `debugger-sa` Service Account is bound to a privileged SCC.**
   - This SCC (`debugger-privileged-scc`) allows the Job to run with hostNetwork, hostPID, hostPath, and privileged container access, and grants required Linux capabilities (NET_ADMIN, NET_RAW, SYS_ADMIN, SYS_PTRACE).
   - This is necessary for node-level debugging and for running commands like `oc debug node` or `nsenter` into pod network namespaces.

4. **RBAC for app1-admin SA is tightly scoped.**
   - The `app1-admin` Service Account in the `app1` namespace is granted only the minimum RBAC permissions in the `debugger` namespace required to:
     - Create Jobs and Pods
     - Get logs from Jobs/Pods
     - Exec into Pods
     - Delete Jobs/Pods
     - Read events
   - This is defined in `app1-admin-sa.yaml` and ensures the app user cannot escalate privileges or perform cluster-wide privileged actions.

5. **Gatekeeper Policy restricts images in the debugger namespace.**
   - A Gatekeeper policy is enforced in the `debugger` namespace to prevent app users from deploying any container images other than the approved debug image. This ensures only trusted debug workloads can run with privileged access.

---

## Key Files and Their Roles

- **run-debugger-job.sh**: Wrapper script for app users to launch debug jobs in the `debugger` namespace.
- **execute-command-configmap.yaml**: ConfigMap containing the main debug script (`execute-command.sh`) used by the Job.
- **debugger-sa**: Service Account in the `debugger` namespace, bound to the privileged SCC.
- **debugger-privileged-scc**: SCC granting privileged container, hostNetwork, hostPID, hostPath, and required capabilities.
- **app1-admin-sa.yaml**: RBAC for the app1-admin Service Account, granting only the permissions needed to launch and monitor debug jobs in the `debugger` namespace.
- **k8s/gatekeeper-debugger-image-policy.yaml**: Gatekeeper policy file that restricts container images in the `debugger` namespace.

---

## Security and Separation of Duties

- **Privileged operations are isolated:** Only the `debugger-sa` in the `debugger` namespace can run privileged containers and access host resources.
- **App users are limited:** The `app1-admin` SA can only create/manage debug jobs and access their logs in the `debugger` namespace, with no direct access to privileged SCC or cluster-wide resources.
- **RBAC is least-privilege:** The permissions in `app1-admin-sa.yaml` are scoped to only what is required for the debug workflow.
- **Gatekeeper policy:** Prevents app users from deploying unapproved images in the `debugger` namespace.
- **Auditing:** All debug job executions and access are auditable via Kubernetes events and logs.

---

## Example Flow

1. **App user runs:**
   ```sh
   ./run-debugger-job.sh <node> <pod> <namespace> tcpdump -i any 60
   ```
2. **Job is created in `debugger` namespace, using `debugger-sa` and privileged SCC.**
3. **Job runs the script from `execute-command-configmap.yaml`, performs the debug operation, and saves results (e.g., pcap files).**
4. **App user can fetch logs and results as permitted by RBAC.**

---

## Summary Table: app1-admin SA Permissions in `debugger` Namespace

| Resource         | Verbs                        | Notes                |
|------------------|-----------------------------|----------------------|
| events           | get, list, watch             | rbac.yaml            |
| pods             | create, get, list, watch     | app1-admin-sa.yaml   |
| pods             | delete                       | app1-admin-sa.yaml   |
| pods/exec        | create                       | app1-admin-sa.yaml   |
| pods/log         | get                          | app1-admin-sa.yaml   |
| jobs (batch)     | get, list, create, delete, watch | app1-admin-sa.yaml|

---

## References
- `run-debugger-job.sh`
- `execute-command-configmap.yaml`
- `debugger-sa` and `debugger-privileged-scc`
- `app1-admin-sa.yaml` (RBAC for app user)
- `k8s/gatekeeper-debugger-image-policy.yaml` (Gatekeeper policy for image restriction)

---

*This document provides a comprehensive context for the OpenShift debug workflow as implemented, with a focus on secure, auditable, and least-privilege access for application users.*
