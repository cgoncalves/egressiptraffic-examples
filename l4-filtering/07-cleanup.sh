#!/bin/bash
set -euo pipefail

kubectl delete egressip eip-oam-l4 --ignore-not-found
kubectl delete egressiptraffic eipt-oam-l4 --ignore-not-found
kubectl delete namespace demo-eipt-l4 --ignore-not-found
kubectl label node ovn-worker2 k8s.ovn.org/egress-assignable- 2>/dev/null || true

# Cleanup Docker infra
docker rm -f oam-server 2>/dev/null || true
docker network disconnect oam-net ovn-worker2 2>/dev/null || true
docker network rm oam-net 2>/dev/null || true

echo "Cleanup complete."
