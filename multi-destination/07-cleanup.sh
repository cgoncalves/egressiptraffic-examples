#!/bin/bash
set -euo pipefail

kubectl delete egressip eip-multi --ignore-not-found
kubectl delete egressiptraffic eipt-multi --ignore-not-found
kubectl delete namespace demo-eipt-multi --ignore-not-found
kubectl label node ovn-worker2 k8s.ovn.org/egress-assignable- 2>/dev/null || true

docker rm -f oam-server1 oam-server2 2>/dev/null || true
docker network disconnect oam-net ovn-worker2 2>/dev/null || true
docker network rm oam-net 2>/dev/null || true

echo "Cleanup complete."
