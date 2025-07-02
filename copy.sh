#!/bin/bash

# Usage: ./download-pcaps.sh <node_name>
node_name="$1"

if [[ -z "$node_name" ]]; then
  echo "❌ Usage: $0 <node_name>"
  exit 1
fi

timestamp=$(date +%s)
tempdir="/host/tmp/pcapcopy-$timestamp"

echo "🔍 Step 1: Copying .pcap files from /var/tmp to $tempdir on node $node_name ..."
oc debug node/$node_name -- bash -c "mkdir -p $tempdir && find /host/var/tmp -type f -name '*.pcap' -exec cp {} $tempdir/ \;"

echo "📦 Step 2: Starting a dummy pod on the node to copy files from it..."
# Create a privileged pod on the same node
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: pcap-copier-$timestamp
spec:
  nodeName: $node_name
  restartPolicy: Never
  containers:
  - name: copier
    image: registry.access.redhat.com/ubi8/ubi
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

echo "⏳ Waiting for pod to be ready..."
oc wait --for=condition=Ready pod/pcap-copier-$timestamp --timeout=30s

echo "📥 Step 3: Copying files from pod to local machine..."
mkdir -p ./pcap-dump
oc cp pcap-copier-$timestamp:$tempdir ./pcap-dump

echo "🧹 Step 4: Cleaning up pod and node temp directory..."
oc delete pod pcap-copier-$timestamp --force --grace-period=0
oc debug node/$node_name -- bash -c "rm -rf $tempdir"

echo "✅ Done! PCAP files are available in ./pcap-dump"

