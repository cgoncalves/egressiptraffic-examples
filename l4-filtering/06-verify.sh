#!/bin/bash
# Verify L4 protocol/port filtering use case.
set -euo pipefail

echo "=== EgressIP status ==="
kubectl get egressip eip-oam-l4 -o jsonpath='{.status}' 2>/dev/null | python3 -m json.tool 2>/dev/null || echo "(no status -- EgressIP not assigned yet)"
echo ""

echo "=== Test 1: HTTP to 192.168.250.1:8080 (TCP, port NOT in EgressIPTraffic) ==="
echo "Expected: traffic should NOT use EgressIP (port 8080 not matched)"
kubectl exec -n demo-eipt-l4 demo-pod -- curl -s --connect-timeout 5 http://192.168.250.1:8080 || echo "(timeout — expected, non-matching port)"
echo ""

echo "=== Test 2: TCP to 192.168.250.1:2222 (matching: TCP port 2222) ==="
echo "Expected: traffic SHOULD use EgressIP (source 192.168.150.101)"
kubectl exec -n demo-eipt-l4 demo-pod -- bash -c 'echo "hello" | nc -w2 192.168.250.1 2222' || echo "(connection failed)"
echo ""

echo "=== Node-side state on ovn-worker2 ==="
echo "--- IP rules (priority 6000 with ipproto/dport) ---"
docker exec ovn-worker2 ip rule show | grep -E "6000" || echo "(none)"
echo ""
echo "Expected: separate rules for each protocol/port combo:"
echo "  from <podIP> to 192.168.250.0/24 ipproto 17 dport 5060 lookup <table>"
echo "  from <podIP> to 192.168.250.0/24 ipproto 6 dport 2222 lookup <table>"
echo ""

echo "=== OVN LRP match (should include L4 conditions) ==="
POD_NODE=$(kubectl get pod -n demo-eipt-l4 demo-pod -o jsonpath='{.spec.nodeName}')
OVNKUBE_POD=$(kubectl get pods -n ovn-kubernetes -l app=ovnkube-node --field-selector spec.nodeName=${POD_NODE} -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n ovn-kubernetes ${OVNKUBE_POD} -c ovnkube-controller -- ovn-nbctl lr-policy-list ovn_cluster_router 2>/dev/null | grep -E " 100 " | head -5
echo ""
echo "Expected match should include: tcp && tcp.dst == 2222, udp && udp.dst == 5060"
