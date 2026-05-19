#!/bin/bash
# Verify multi-destination EgressIPTraffic use case.
set -euo pipefail

kubectl wait -n demo-eipt-multi pod/demo-pod --for=condition=Ready --timeout=60s 2>/dev/null || true

echo "=== EgressIP status ==="
kubectl get egressip eip-multi -o jsonpath='{.status}' 2>/dev/null | python3 -m json.tool 2>/dev/null || echo "(no status -- EgressIP not assigned yet)"
echo ""

echo "=== Test 1: Traffic to 192.168.150.100 (first destination) ==="
echo "Expected source: 192.168.150.101 (EgressIP)"
kubectl exec -n demo-eipt-multi demo-pod -- curl -s --connect-timeout 5 http://192.168.150.100:8080
echo ""

echo "=== Test 2: Traffic to 192.168.150.200 (second destination) ==="
echo "Expected source: 192.168.150.101 (EgressIP)"
kubectl exec -n demo-eipt-multi demo-pod -- curl -s --connect-timeout 5 http://192.168.150.200:8081
echo ""

echo "=== IP rules on ovn-worker2 ==="
docker exec ovn-worker2 ip rule show | grep -E "600[01]" || echo "(none)"
echo ""
echo "Both 192.168.150.100/32 and 192.168.150.200/32 should appear as destination rules."
