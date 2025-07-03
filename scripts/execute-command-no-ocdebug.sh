#!/bin/bash
# execute-command-no-ocdebug.sh - Like execute-command.sh, but does NOT use 'oc debug node'.
# Assumes this script runs in a privileged pod/job on the target node with hostNetwork, hostPID, and /host mounts.
# Usage: ./execute-command-no-ocdebug.sh <node-name> <pod-name> <pod-namespace> <command> [arguments...] <timeout>

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"; }

# Validate command
validate_command() {
  local cmd="$1"
  if [[ "$cmd" != "tcpdump" && "$cmd" != "ncat" && "$cmd" != "ip" && "$cmd" != "ifconfig" ]]; then
    error "Only 'tcpdump', 'ncat', 'ip', and 'ifconfig' commands are allowed"
    exit 1
  fi
}

# Validate tcpdump args (no -c allowed)
validate_tcpdump_args() {
  local args="$@"
  if echo "$args" | grep -E ">(\||>>|\||exec|system|&)" > /dev/null; then
    error "Dangerous tcpdump options detected"
    exit 1
  fi
  if echo "$args" | grep -E "\-w" > /dev/null; then
    if ! echo "$args" | grep -E "\-w\s+/host/var/tmp/" > /dev/null; then
      error "tcpdump output files must be written to /host/var/tmp/ directory"
      exit 1
    fi
  fi
  if echo "$args" | grep -E '\-c( |$)' > /dev/null; then
    error "The -c option is not supported. Use only the timeout value to control capture duration."
    exit 1
  fi
}

# Validate ncat args
validate_ncat_args() {
  local args="$@"
  if echo "$args" | grep -E "(--exec|--sh-exec|-e|>|>>|\||&)" > /dev/null; then
    error "Dangerous ncat options detected"
    exit 1
  fi
}

# Validate network command
validate_network_command() {
  local cmd="$1"; shift; local args="$@"
  if [[ "$cmd" == "ip" ]]; then
    if echo "$args" | grep -E -wq '(add|del|delete|flush|set|change|replace|link set|route add|route del|route flush|neigh add|neigh del|neigh flush|tunnel add|tunnel del|tunnel change|tunnel set|address add|address del|address flush|addr add|addr del|addr flush|rule add|rule del|rule flush|maddress add|maddress del|maddress flush|mroute add|mroute del|mroute flush|monitor|xfrm|tcp_metrics|token|macsec|vrf|netns|netconf|netem|qdisc|class|filter|mptcp|sr|srdev|srpolicy|srroute|srseg|srlabel|srencap|sren|srdecap|srpop|srpush|srpophead|srpoptail|srpopall|srpopalltail|srpopallhead|srpopalltailheadall|srpopalltailheadallpop|srpopalltailheadallpopall|srpopalltailheadallpopallpop|srpopalltailheadallpopallpopall|srpopalltailheadallpopallpopallpop|srpopalltailheadallpopallpopallpopallpop|srpopalltailheadallpopallpopallpopallpopall|srpopalltailheadallpopallpopallpopallpopallpop|srpopalltailheadallpopallpopallpopallpopallpopall|srpopalltailheadallpopallpopallpopallpopallpopallpop|srpopalltailheadallpopallpopallpopallpopallpopallpopall|srpopalltailheadallpopallpopallpopallpopallpopallpopallpop)' ; then
      error "Modifying 'ip' subcommands are not allowed. Only read-only queries are permitted."
      exit 1
    fi
  elif [[ "$cmd" == "ifconfig" ]]; then
    return 0
  else
    error "Only 'tcpdump', 'ncat', 'ip', and 'ifconfig' commands are allowed."
    exit 1
  fi
}

main() {
  if [[ $# -lt 5 ]]; then
    echo "Usage: $0 <node-name> <pod-name> <pod-namespace> <command> [arguments...] <timeout>"
    exit 1
  fi
  local node_name="$1"; local pod_name="$2"; local namespace="$3"; local command="$4"; shift 4
  # Timeout is always the last argument
  local timeout="${!#}"
  set -- "$@"
  set -- "${@:1:$(($#-1))}" # Remove last arg (timeout) from $@
  local args="$@"
  validate_command "$command"

  # Try to get the PID of the target pod (if possible)
  POD_PID=""
  if [[ -n "$pod_name" && -n "$namespace" ]]; then
    # Try to get the infra container PID from /host/proc or crictl (if available)
    # This is a best-effort guess for logging
    POD_PID=$(grep -l "^NStgid:" /host/proc/*/status 2>/dev/null | xargs -I{} sh -c 'grep -q "$pod_name" {} && echo {}' | head -n1 | awk -F'/' '{print $4}')
    if [[ -n "$POD_PID" ]]; then
      log "Target pod PID: $POD_PID"
    else
      warn "Could not determine pod PID."
    fi
  fi

  # If using nsenter, print the command
  if [[ -n "$POD_PID" ]]; then
    NSENTER_CMD="nsenter -t $POD_PID -n -- $command $args"
    log "nsenter command: $NSENTER_CMD"
  fi

  if [[ "$command" == "tcpdump" ]]; then
    validate_tcpdump_args $args
    # Always use -i any
    if ! echo "$args" | grep -E '\-i[ ]*[^ ]+' > /dev/null; then
      args="-i any $args"
    fi
    mkdir -p /host/var/tmp
    if ! echo "$args" | grep -q "\-w"; then
      OUTPUT_FILE="/host/var/tmp/${node_name}_$(date +%d_%m_%Y-%H_%M_%S-%Z).pcap"
      args="-w $OUTPUT_FILE $args"
      echo "Output will be saved to: $OUTPUT_FILE"
    fi
    echo "Running tcpdump for $timeout seconds..."
    timeout --preserve-status $timeout tcpdump -nn $args
    result=$?
    if [[ $result -eq 124 ]]; then
      echo "tcpdump completed after timeout ($timeout seconds)"; result=0
    fi
    echo "Generated pcap files:"; ls -la /host/var/tmp/*.pcap 2>/dev/null || echo "No pcap files found"
    exit $result
  elif [[ "$command" == "ncat" ]]; then
    validate_ncat_args $args
    echo "Running ncat..."
    ncat $args
  elif [[ "$command" == "ip" || "$command" == "ifconfig" ]]; then
    validate_network_command "$command" $args
    $command $args
  else
    error "Unsupported command: $command"
    exit 1
  fi
}

main "$@"
