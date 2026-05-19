#!/bin/bash
# Verify L4 protocol/port filtering use case.
set -euo pipefail

kubectl wait -n demo-eipt-l4 pod/demo-pod --for=condition=Ready --timeout=60s 2>/dev/null || true

echo "=== EgressIP status ==="
kubectl get egressip eip-oam-l4 -o jsonpath='{.status}' 2>/dev/null | python3 -m json.tool 2>/dev/null || echo "(no status -- EgressIP not assigned yet)"
echo ""

echo "=== Test 1: TCP to 192.168.150.100:8080 (matching: TCP port 8080) ==="
echo "Expected: traffic SHOULD use EgressIP (source 192.168.150.101)"
kubectl exec -n demo-eipt-l4 demo-pod -- curl -s --connect-timeout 5 http://192.168.150.100:8080
echo ""

echo "=== Node-side state on ovn-worker2 ==="
echo "--- IP rules (priority 6000 with ipproto/dport) ---"
docker exec ovn-worker2 ip rule show | grep -E "6000" || echo "(none)"
echo ""
echo "Expected: rule for TCP port 8080:"
echo "  from <podIP> to 192.168.150.0/24 ipproto 6 dport 8080 lookup <table>"
echo ""

echo "=== OVN LRP match (should include L4 conditions) ==="
POD_NODE=$(kubectl get pod -n demo-eipt-l4 demo-pod -o jsonpath='{.spec.nodeName}')
OVNKUBE_POD=$(kubectl get pods -n ovn-kubernetes -l app=ovnkube-node --field-selector spec.nodeName=${POD_NODE} -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n ovn-kubernetes ${OVNKUBE_POD} -c ovnkube-controller -- ovn-nbctl lr-policy-list ovn_cluster_router 2>/dev/null | grep -E " 100 " | head -5
echo ""
echo "Expected match should include: tcp && tcp.dst == 8080"
