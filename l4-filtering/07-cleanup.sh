#!/bin/bash
set -euo pipefail

kubectl delete egressip eip-oam-l4 --ignore-not-found
kubectl delete egressiptraffic eipt-oam-l4 --ignore-not-found
kubectl delete namespace demo-eipt-l4 --ignore-not-found
kubectl label node ovn-worker2 k8s.ovn.org/egress-assignable- 2>/dev/null || true

docker exec ovn-worker2 ip netns del oam 2>/dev/null || true
docker exec ovn-worker2 ip link del oam-host 2>/dev/null || true

echo "Cleanup complete."
