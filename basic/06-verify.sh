#!/bin/bash
# Verify the basic EgressIPTraffic use case.
set -euo pipefail

echo "=== EgressIP status ==="
kubectl get egressip eip-net1 -o jsonpath='{.status}' 2>/dev/null | python3 -m json.tool 2>/dev/null || echo "(no status -- EgressIP not assigned yet)"
echo ""

echo "=== Test 1: Traffic to 192.168.250.1 (matching destination) ==="
echo "Expected source: 192.168.150.101 (EgressIP)"
kubectl exec -n demo-eipt demo-pod -- curl -s --connect-timeout 5 http://192.168.250.1:8080
echo ""

echo "=== Node-side state on ovn-worker2 ==="
echo "--- IP rules (priority 6000 = trafficSelector) ---"
docker exec ovn-worker2 ip rule show | grep -E "600[01]" || echo "(none)"
echo ""
echo "--- Routing table for EgressIP interface ---"
LINK_INDEX=$(docker exec ovn-worker2 cat /sys/class/net/oam-host/ifindex)
TABLE_ID=$((1000 + LINK_INDEX))
docker exec ovn-worker2 ip route show table "${TABLE_ID}" 2>/dev/null || echo "(no custom table)"
echo ""
echo "--- iptables SNAT rules ---"
docker exec ovn-worker2 iptables -t nat -S OVN-KUBE-SNAT-MGMTPORT 2>/dev/null | grep 192.168.150.101 || echo "(none)"
