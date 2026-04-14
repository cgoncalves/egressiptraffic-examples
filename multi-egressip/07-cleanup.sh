#!/bin/bash
set -euo pipefail

kubectl delete egressip eip-net1 eip-net2 --ignore-not-found
kubectl delete egressiptraffic eipt-net1 eipt-net2 --ignore-not-found
kubectl delete namespace demo-eipt-multi-eip --ignore-not-found
kubectl label node ovn-worker2 k8s.ovn.org/egress-assignable- 2>/dev/null || true

for ns in oam signaling; do
    docker exec ovn-worker2 ip netns del ${ns} 2>/dev/null || true
done
docker exec ovn-worker2 ip link del oam-host 2>/dev/null || true
docker exec ovn-worker2 ip link del sig-host 2>/dev/null || true

echo "Cleanup complete."
