#!/bin/bash
# Verify the basic EgressIPTraffic use case.
set -euo pipefail

kubectl wait -n demo-eipt pod/demo-pod --for=condition=Ready --timeout=60s 2>/dev/null || true

echo "=== EgressIP status ==="
kubectl get egressip eip-net1 -o jsonpath='{.status}' 2>/dev/null | python3 -m json.tool 2>/dev/null || echo "(no status -- EgressIP not assigned yet)"
echo ""

echo "=== Test 1: Traffic to 192.168.150.100 (matching destination) ==="
echo "Expected source: 192.168.150.101 (EgressIP)"
kubectl exec -n demo-eipt demo-pod -- curl -s --connect-timeout 5 http://192.168.150.100:8080
echo ""

echo "=== Node-side state on ovn-worker2 ==="
echo "--- IP rules (priority 6000 = trafficSelector) ---"
docker exec ovn-worker2 ip rule show | grep -E "600[01]" || echo "(none)"
echo ""
echo "--- iptables SNAT rules ---"
docker exec ovn-worker2 iptables -t nat -S OVN-KUBE-SNAT-MGMTPORT 2>/dev/null | grep 192.168.150.101 || echo "(none)"
