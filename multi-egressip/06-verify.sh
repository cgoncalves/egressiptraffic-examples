#!/bin/bash
# Verify multi-EgressIP use case: two trafficSelector EgressIPs on the same pod,
# each routing to different destination networks via different interfaces.
set -euo pipefail

echo "=== EgressIP statuses ==="
echo "--- eip-net1 (oam traffic to 192.168.250.0/24 via 192.168.150.101) ---"
kubectl get egressip eip-net1 -o jsonpath='{.status}' 2>/dev/null | python3 -m json.tool 2>/dev/null || echo "(no status -- EgressIP not assigned yet)"
echo ""
echo "--- eip-net2 (signaling traffic to 192.168.251.0/24 via 192.168.200.101) ---"
kubectl get egressip eip-net2 -o jsonpath='{.status}' 2>/dev/null | python3 -m json.tool 2>/dev/null || echo "(no status -- EgressIP not assigned yet)"
echo ""

echo "=== Test 1: Traffic to 192.168.250.1 (oam destination) ==="
echo "Expected source: 192.168.150.101 (eip-net1)"
kubectl exec -n demo-eipt-multi-eip demo-pod -- curl -s --connect-timeout 5 http://192.168.250.1:8080
echo ""

echo "=== Test 2: Traffic to 192.168.251.1 (signaling destination) ==="
echo "Expected source: 192.168.200.101 (eip-net2)"
kubectl exec -n demo-eipt-multi-eip demo-pod -- curl -s --connect-timeout 5 http://192.168.251.1:8081
echo ""

echo "=== IP rules on ovn-worker2 (priority 6000 = trafficSelector) ==="
docker exec ovn-worker2 ip rule show | grep "6000" || echo "(none)"
echo ""
echo "Each destination CIDR should have its own IP rule pointing to a different routing table."
