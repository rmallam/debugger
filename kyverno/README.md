# Kyverno Policies for Security and Compliance

This folder contains Kyverno policies designed for Kubernetes clusters with a focus on security, compliance, and proper resource management. Kyverno is a policy engine designed for Kubernetes that helps you validate, mutate, and generate resources using policies written in YAML.

## Table of Contents
- [Installation](#installation)
- [Policy Overview](#policy-overview)
- [Individual Policy Details](#individual-policy-details)
- [ACM Integration](#acm-integration)
- [Usage Examples](#usage-examples)
- [Troubleshooting](#troubleshooting)

## Installation

### Prerequisites
- openshift cluster
- `oc` configured to access your cluster
- Cluster admin permissions

### Installing Kyverno

#### Method 1: Direct Installation (Recommended)
```bash
oc create -f https://github.com/kyverno/kyverno/releases/latest/download/install.yaml
```

#### Method 2: Using Helm
```bash
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update
helm install kyverno kyverno/kyverno --namespace kyverno --create-namespace
```

#### Method 3: Using OpenShift
```bash
oc create -f https://github.com/kyverno/kyverno/releases/latest/download/install.yaml
```

### Verify Installation
```bash
oc get pods -n kyverno
oc get crd | grep kyverno
```

## Policy Overview

This repository contains security-focused policies that enforce:
- **Namespace labeling requirements** for organizational compliance
- **SecurityContextConstraint (SCC) restrictions** for OpenShift environments
- **Deployment-specific security controls** for privileged workloads
- **Automated namespace management** for ACM policy deployment

## Individual Policy Details

### 1. Namespace Labeling Policy (`label-clysterpolicy.yaml`)

**Purpose**: Ensures all namespaces have required team labels for proper governance and resource tracking.

**What it does**:
- Validates that every namespace has a `team` label
- Blocks namespace creation if the label is missing
- Helps with cost allocation and access control

**Configuration**:
```yaml
validationFailureAction: Enforce  # Blocks non-compliant resources
background: false                 # Only validates new requests
```

**Usage**:
```bash
# Apply the policy
oc apply -f label-clysterpolicy.yaml

# Test with a compliant namespace
oc create namespace test-ns --dry-run=server -o yaml | \
  oc label --local -f - team=devops -o yaml | \
  oc apply -f -

# This will be blocked (no team label)
oc create namespace bad-ns
```

### 2. NSP SCC Restriction Policy (`policygen-scc-restriction.yaml`)

**Purpose**: Restricts the usage of the NSP (Network Service Platform) SecurityContextConstraint to authorized deployments only.

**What it does**:
- Allows NSP SCC usage only for `nsp-deployment` in the `NSP` namespace
- Requires the deployment to use the `docker.io/nsp` image
- Prevents privilege escalation by unauthorized workloads

**Security Benefits**:
- Prevents unauthorized pods from using privileged SCCs
- Ensures only vetted deployments can access network-level privileges
- Maintains audit trail of privileged access

**Configuration Details**:
```yaml
validationFailureAction: Enforce  # Strictly enforces the policy
background: true                  # Validates existing and new resources
```

**Usage**:
```bash
# Apply the policy
oc apply -f policygen-scc-restriction.yaml

# Authorized deployment (will succeed)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nsp-deployment
  namespace: NSP
spec:
  template:
    spec:
      containers:
      - name: nsp
        image: docker.io/nsp:latest
```

## ACM Integration

The `acm/` folder contains policies specifically designed for Red Hat Advanced Cluster Management (ACM) for Kubernetes, enabling centralized policy management across multiple clusters.

### ACM Components Overview

#### 1. PolicyGenerator (`policyGenerator.yaml` & `foundation-policyGenerator.yaml`)

**Purpose**: Automates the creation and deployment of policies across managed clusters.

**Key Features**:
- **Cluster Selection**: Uses label selectors to target specific clusters
- **Remediation Control**: Configurable enforcement levels (inform/enforce)
- **Namespace Management**: Automatic policy namespace creation

**Configuration Example**:
```yaml
policyDefaults:
  namespace: policies
  placement:
    labelSelector:
      environment: prod  # Targets production clusters
  remediationAction: enforce
```

#### 2. Foundation Policy (`foundation-policyGenerator.yaml`)

**Purpose**: Creates prerequisite infrastructure (namespaces) before deploying security policies.

**Workflow**:
1. **Step 1**: Creates the `policies` namespace on target clusters
2. **Step 2**: Deploys SCC restriction policies
3. **Step 3**: Ensures proper sequencing and dependencies

#### 3. SCC Policy for ACM (`acm/policy.yaml`)

**Enhanced Features**:
- Supports multiple authorized deployments: `splunk-universal-forwarder`, `debugger-job`
- Allows multiple authorized images: `splunk/universalforwarder:*`, `debugger:*`
- Flexible configuration for different environments

### ACM Deployment Workflow

#### Step 1: Prepare Your Hub Cluster
```bash
# Ensure ACM is installed and configured
oc get managedclusters

# Verify policy namespace exists on hub
oc get namespace policies
```

#### Step 2: Label Your Managed Clusters
```bash
# Label clusters for policy targeting
oc label managedcluster <cluster-name> environment=prod
oc label managedcluster <cluster-name> rhdp_usage=development
```

#### Step 3: Deploy Foundation Policies
```bash
# Apply the foundation policy generator
oc apply -f acm/foundation-policyGenerator.yaml

# Verify policy creation
oc get policies -n policies
oc get placementbindings -n policies
```

#### Step 4: Monitor Policy Compliance
```bash
# Check policy status across clusters
oc get policies -A
oc describe policy <policy-name> -n policies

# View compliance details
oc get policyreports -A
```

## Usage Examples

### Example 1: Testing Namespace Policy Compliance
```bash
# This will succeed (has required label)
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: compliant-ns
  labels:
    team: platform-engineering
EOF

# This will be blocked (missing team label)
oc create namespace non-compliant-ns
```

### Example 2: Testing SCC Policy with Authorized Deployment
```bash
# Create authorized deployment
cat <<EOF | oc apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: debugger-job
  namespace: debug-tools
spec:
  replicas: 1
  selector:
    matchLabels:
      app: debugger
  template:
    metadata:
      labels:
        app: debugger
      annotations:
        openshift.io/scc: privileged
    spec:
      containers:
      - name: debugger
        image: debugger:latest
        securityContext:
          privileged: true
EOF
```

### Example 3: ACM Policy Management
```bash
# Deploy policies to development clusters only
cat <<EOF | oc apply -f -
apiVersion: policy.open-cluster-management.io/v1
kind: PolicyGenerator
metadata:
  name: dev-policies
policyDefaults:
  namespace: policies
  placement:
    labelSelector:
      rhdp_usage: development
  remediationAction: inform  # Report-only for dev
policies:
  - name: security-baseline
    manifests:
      - path: ../label-clysterpolicy.yaml
      - path: ../policygen-scc-restriction.yaml
EOF
```

## Troubleshooting

### Common Issues and Solutions

#### 1. Policy Not Enforcing
```bash
# Check if Kyverno is running
oc get pods -n kyverno

# Verify policy is applied correctly
oc get cpol
oc describe cpol <policy-name>

# Check for validation failures
oc get events --field-selector reason=PolicyViolation
```

#### 2. ACM Policy Issues
```bash
# Check policy compliance status
oc get policies -A -o wide

# Verify cluster labels
oc get managedclusters --show-labels

# Check placement rules
oc get placementrules -A
oc describe placementrule <rule-name>
```

#### 3. SCC Policy Debugging
```bash
# Check current SCCs
oc get scc

# Verify pod annotations
oc get pods -o jsonpath='{.items[*].metadata.annotations}'

# Review policy conditions
oc describe cpol restrict-nsp-scc
```

### Policy Testing Best Practices

1. **Use Dry-Run**: Test policies with `--dry-run=server` before applying
2. **Start with Audit Mode**: Set `validationFailureAction: Audit` initially
3. **Monitor Events**: Watch for policy violations in cluster events
4. **Gradual Rollout**: Deploy to development clusters first

## Policy Customization

### Modifying Label Requirements
Edit `label-clysterpolicy.yaml` to change required labels:
```yaml
validate:
  pattern:
    metadata:
      labels:
        team: "?*"           # Requires any team value
        environment: "?*"    # Add environment requirement
        cost-center: "?*"    # Add cost center requirement
```

### Adding New Authorized Deployments
Update the SCC policy to include additional authorized deployments:
```yaml
- key: "{{ request.object.metadata.ownerReferences[0].name }}"
  operator: NotIn
  value: 
    - "splunk-universal-forwarder"
    - "debugger-job"
    - "your-new-deployment"  # Add your deployment here
```

## Additional Resources

- [Kyverno Documentation](https://kyverno.io/docs/)
- [Kyverno Policy Examples](https://kyverno.io/policies/)
- [ACM Policy Documentation](https://access.redhat.com/documentation/en-us/red_hat_advanced_cluster_management_for_kubernetes/)
- [OpenShift SCC Documentation](https://docs.openshift.com/container-platform/latest/authentication/managing-security-context-constraints.html)

For questions or issues, please refer to the project documentation or create an issue in the repository.