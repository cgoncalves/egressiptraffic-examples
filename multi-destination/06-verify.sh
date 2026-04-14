#!/bin/bash
# Verify multi-destination EgressIPTraffic use case.
set -euo pipefail

echo "=== EgressIP status ==="
kubectl get egressip eip-multi -o jsonpath='{.status}' 2>/dev/null | python3 -m json.tool 2>/dev/null || echo "(no status — EgressIP not assigned yet)"
echo ""

echo "=== Test 1: Traffic to 192.168.250.1 (first destination network) ==="
echo "Expected source: 192.168.150.101 (EgressIP)"
kubectl exec -n demo-eipt-multi demo-pod -- curl -s --connect-timeout 5 http://192.168.250.1:8080
echo ""

echo "=== Test 2: Traffic to 192.168.251.1 (second destination network) ==="
echo "Expected source: 192.168.150.101 (EgressIP)"
kubectl exec -n demo-eipt-multi demo-pod -- curl -s --connect-timeout 5 http://192.168.251.1:8081
echo ""

echo "=== Routing table on ovn-worker2 ==="
LINK_INDEX=$(docker exec ovn-worker2 cat /sys/class/net/oam-host/ifindex)
TABLE_ID=$((1000 + LINK_INDEX))
echo "Table ${TABLE_ID}:"
docker exec ovn-worker2 ip route show table "${TABLE_ID}" 2>/dev/null || echo "(empty)"
echo ""
echo "Both 192.168.250.0/24 and 192.168.251.0/24 should appear as destination routes."
