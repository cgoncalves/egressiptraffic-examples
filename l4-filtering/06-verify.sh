#!/bin/bash
# Verify L4 protocol/port filtering use case.
set -euo pipefail

PASS() { echo -e "\033[32mPASS\033[0m: $1"; }
FAIL() { echo -e "\033[31mFAIL\033[0m: $1"; FAILURES=$((FAILURES+1)); }
FAILURES=0

kubectl wait -n demo-eipt-l4 pod/demo-pod --for=condition=Ready --timeout=60s 2>/dev/null || true

echo "=== EgressIP status ==="
kubectl get egressip eip-oam-l4 -o jsonpath='{.status}' 2>/dev/null | python3 -m json.tool 2>/dev/null || echo "(no status -- EgressIP not assigned yet)"
echo ""

echo "=== Test 1: TCP to 192.168.250.100:8080 (matching: TCP port 8080, via router) ==="
src=$(kubectl exec -n demo-eipt-l4 demo-pod -- curl -s --connect-timeout 5 http://192.168.250.100:8080 2>/dev/null | grep -oP 'client=\K[0-9.]+')
if [ "$src" = "192.168.150.101" ]; then
    PASS "TCP traffic to matching port uses EgressIP (source: $src)"
else
    FAIL "Expected source 192.168.150.101, got: ${src:-timeout}"
fi

echo ""
echo "=== Node-side state on ovn-worker2 ==="
echo "--- IP rules (priority 6000 with ipproto/dport) ---"
docker exec ovn-worker2 ip rule show | grep -E "6000" || echo "(none)"
echo ""
echo "--- EgressIP address on interface ---"
docker exec ovn-worker2 ip -4 addr show | grep "192.168.150.101" || echo "(not found)"
echo ""
echo "--- iptables SNAT rules ---"
docker exec ovn-worker2 iptables -t nat -S OVN-KUBE-EGRESS-IP-MULTI-NIC 2>/dev/null | grep -E "192.168.150.101|192.168.200.101" || echo "(none)"

echo ""
echo "=== OVN LRP match ==="
POD_NODE=$(kubectl get pod -n demo-eipt-l4 demo-pod -o jsonpath='{.spec.nodeName}')
OVNKUBE_POD=$(kubectl get pods -n ovn-kubernetes -l app=ovnkube-node --field-selector spec.nodeName=${POD_NODE} -o jsonpath='{.items[0].metadata.name}')
lrp=$(kubectl exec -n ovn-kubernetes ${OVNKUBE_POD} -c ovnkube-controller -- ovn-nbctl lr-policy-list ovn_cluster_router 2>/dev/null | grep -E " 100 " | head -1)
echo "$lrp"
if echo "$lrp" | grep -q "tcp.*tcp.dst == 8080"; then
    PASS "OVN LRP includes L4 match: tcp && tcp.dst == 8080"
else
    FAIL "OVN LRP missing expected L4 match condition"
fi

echo ""
if [ $FAILURES -eq 0 ]; then
    echo -e "\033[32mAll tests passed.\033[0m"
else
    echo -e "\033[31m${FAILURES} test(s) failed.\033[0m"
    exit 1
fi
