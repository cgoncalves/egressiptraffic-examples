#!/bin/bash
# Cleanup all resources created by this use case.
set -euo pipefail

kubectl delete egressip eip-oam --ignore-not-found
kubectl delete egressiptraffic eipt-oam --ignore-not-found
kubectl delete namespace demo-eipt --ignore-not-found
kubectl label node ovn-worker2 k8s.ovn.org/egress-assignable- 2>/dev/null || true

# Cleanup network infra on egress node
docker exec ovn-worker2 ip netns del oam 2>/dev/null || true
docker exec ovn-worker2 ip link del oam-veth-host 2>/dev/null || true

echo "Cleanup complete."
