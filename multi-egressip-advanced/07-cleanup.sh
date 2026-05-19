#!/bin/bash
set -euo pipefail

kubectl delete egressip eip-default eip-sip eip-signaling --ignore-not-found
kubectl delete egressiptraffic eipt-sip eipt-signaling --ignore-not-found
kubectl delete namespace demo-eipt-advanced --ignore-not-found
kubectl label node ovn-worker2 k8s.ovn.org/egress-assignable- 2>/dev/null || true
kubectl label node ovn-worker3 k8s.ovn.org/egress-assignable- 2>/dev/null || true

# Cleanup infra
docker rm -f oam-router sig-router 2>/dev/null || true
docker network disconnect oam-link-net ovn-worker2 2>/dev/null || true
docker network disconnect sig-link-net ovn-worker2 2>/dev/null || true
docker network disconnect sig-link-net ovn-worker3 2>/dev/null || true
docker network rm oam-link-net sig-link-net 2>/dev/null || true

echo "Cleanup complete."
