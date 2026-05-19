#!/bin/bash
set -euo pipefail

kubectl delete egressip eip-default eip-sip eip-signaling --ignore-not-found
kubectl delete egressiptraffic eipt-sip eipt-signaling --ignore-not-found
kubectl delete namespace demo-eipt-advanced --ignore-not-found
kubectl label node ovn-worker2 k8s.ovn.org/egress-assignable- 2>/dev/null || true
kubectl label node ovn-worker3 k8s.ovn.org/egress-assignable- 2>/dev/null || true

# OAM netns on ovn-worker2
docker exec ovn-worker2 ip netns del oam 2>/dev/null || true
docker exec ovn-worker2 ip link del oam-host 2>/dev/null || true

# Signaling Docker network and container
docker rm -f sig-ext 2>/dev/null || true
docker network disconnect sig-net ovn-worker2 2>/dev/null || true
docker network disconnect sig-net ovn-worker3 2>/dev/null || true
docker network rm sig-net 2>/dev/null || true

echo "Cleanup complete."
