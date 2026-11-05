#!/bin/bash
# Author: Madhu Akula
# This program has been created as part of Kubernetes Goat
# Kubernetes Goat Access vulnerable infrastructure
#
# Patched: forwards Services (not Pods), auto-detects or accepts a namespace,
# binds to 127.0.0.1 by default, tracks PIDs and supports --stop.
#
# Usage:
#   bash access-kubernetes-goat.sh                     # find each service in any namespace
#   bash access-kubernetes-goat.sh -n kubernetes-goat  # all services in one namespace
#   bash access-kubernetes-goat.sh --stop              # stop the port-forwards
#
# Options:
#   -n, --namespace NS   Look for all Kubernetes Goat services in NS
#                        (default: find each service in any namespace)
#   --address ADDR       Local bind address (default 127.0.0.1).
#                        Avoid 0.0.0.0: it exposes vulnerable apps to your network.
#   --kubeconfig FILE    Use this kubeconfig
#   --insecure           Skip TLS verification (self-signed clusters)
#   --timeout SECONDS    How long to wait for each service's pods (default 300)
#   --stop               Stop port-forwards started by this script
#   -h, --help           Show this help

NAMESPACE=""
ADDRESS="127.0.0.1"
TIMEOUT=300
STOP=""
KUBECTL_ARGS=()
PIDFILE="${TMPDIR:-/tmp}/kubernetes-goat-port-forwards.pids"

# service-name:local-port:service-port
FORWARDS=(
  "build-code-service:1230:3000"           # Sensitive keys in codebases
  "health-check-service:1231:80"           # DIND (docker-in-docker) exploitation
  "internal-proxy-api-service:1232:3000"   # SSRF in the Kubernetes world
  "system-monitor-service:1233:8080"       # Container escape to the host system
  "kubernetes-goat-home-service:1234:80"   # Kubernetes Goat home
  "poor-registry-service:1235:5000"        # Attacking private registry
  "hunger-check-service:1236:8080"         # DoS the memory/CPU resources
)

usage() {
  sed -n '/^# Usage:/,/^# *-h, --help/p' "$0" | sed 's/^# \{0,1\}//'
}

need_value() {
  if [[ -z "${2:-}" ]]; then echo "$1 needs a value"; usage; exit 1; fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--namespace) need_value "$1" "${2:-}"; NAMESPACE="$2"; shift 2 ;;
    --address)      need_value "$1" "${2:-}"; ADDRESS="$2"; shift 2 ;;
    --kubeconfig)   need_value "$1" "${2:-}"; KUBECTL_ARGS+=(--kubeconfig "$2"); shift 2 ;;
    --timeout)      need_value "$1" "${2:-}"; TIMEOUT="$2"; shift 2 ;;
    --insecure)     KUBECTL_ARGS+=(--insecure-skip-tls-verify); shift ;;
    --stop)         STOP="yes"; shift ;;
    -h|--help)      usage; exit 0 ;;
    *)              echo "unknown arg: $1"; usage; exit 1 ;;
  esac
done

k() { kubectl "${KUBECTL_ARGS[@]}" "$@"; }

stop_forwards() {
  if [[ -f "$PIDFILE" ]]; then
    while read -r pid; do kill "$pid" 2>/dev/null; done < "$PIDFILE"
    rm -f "$PIDFILE"
    echo "Stopped Kubernetes Goat port-forwards."
  else
    echo "No port-forwards recorded in $PIDFILE."
  fi
}

if [[ -n "$STOP" ]]; then
  stop_forwards
  exit 0
fi

# Refuse to start a second set while the first is still running
if [[ -f "$PIDFILE" ]]; then
  alive=0
  while read -r pid; do kill -0 "$pid" 2>/dev/null && alive=1; done < "$PIDFILE"
  if (( alive )); then
    echo "Port-forwards are already running. Run: bash $0 --stop"
    exit 1
  fi
  rm -f "$PIDFILE"
fi

if ! k version >/dev/null 2>&1; then
  echo "Please check kubectl setup."
  exit 1
fi
echo "kubectl setup looks good."

if [[ "$ADDRESS" != "127.0.0.1" && "$ADDRESS" != "localhost" ]]; then
  echo "WARNING: binding to $ADDRESS exposes intentionally vulnerable apps beyond this machine."
fi

find_namespace() {
  local svc="$1"
  if [[ -n "$NAMESPACE" ]]; then
    k -n "$NAMESPACE" get svc "$svc" >/dev/null 2>&1 && echo "$NAMESPACE"
  else
    k get svc -A --field-selector "metadata.name=$svc" \
      -o jsonpath='{.items[0].metadata.namespace}' 2>/dev/null
  fi
}

wait_for_endpoints() {
  local ns="$1" svc="$2" waited=0 ips
  while (( waited < TIMEOUT )); do
    ips=$(k -n "$ns" get endpoints "$svc" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)
    [[ -n "$ips" ]] && return 0
    echo "  $svc has no ready pods yet, retrying in 10s..."
    sleep 10
    waited=$((waited + 10))
  done
  return 1
}

echo "Port-forwarding Kubernetes Goat services to $ADDRESS (ports 1230-1236)"
failed=0
for entry in "${FORWARDS[@]}"; do
  IFS=: read -r svc lport rport <<< "$entry"

  ns=$(find_namespace "$svc")
  if [[ -z "$ns" ]]; then
    echo "SKIP  $svc: service not found${NAMESPACE:+ in namespace $NAMESPACE}"
    failed=$((failed + 1))
    continue
  fi

  if ! wait_for_endpoints "$ns" "$svc"; then
    echo "SKIP  $svc ($ns): no ready pods after ${TIMEOUT}s"
    failed=$((failed + 1))
    continue
  fi

  nohup kubectl "${KUBECTL_ARGS[@]}" -n "$ns" port-forward --address "$ADDRESS" \
    "svc/$svc" "$lport:$rport" >/dev/null 2>&1 &
  pid=$!
  sleep 1
  if kill -0 "$pid" 2>/dev/null; then
    echo "$pid" >> "$PIDFILE"
    echo "OK    http://$ADDRESS:$lport  ->  $ns/$svc:$rport"
  else
    echo "FAIL  $svc: port-forward exited (is local port $lport already in use?)"
    failed=$((failed + 1))
  fi
done

echo
if (( failed )); then
  echo "$failed forward(s) not started; see messages above."
fi
echo "Visit http://$ADDRESS:1234 to get started with your Kubernetes Goat hacking!"
echo "Stop with: bash $0 --stop"