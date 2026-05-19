#!/bin/bash
set -euo pipefail

kubectl delete egressip eip-net1 eip-net2 --ignore-not-found
kubectl delete egressiptraffic eipt-net1 eipt-net2 --ignore-not-found
kubectl delete namespace demo-eipt-multi-eip --ignore-not-found
kubectl label node ovn-worker2 k8s.ovn.org/egress-assignable- 2>/dev/null || true

# Cleanup infra
docker rm -f oam-router sig-router 2>/dev/null || true
docker network disconnect oam-link-net ovn-worker2 2>/dev/null || true
docker network disconnect sig-link-net ovn-worker2 2>/dev/null || true
docker network rm oam-link-net sig-link-net 2>/dev/null || true

echo "Cleanup complete."
