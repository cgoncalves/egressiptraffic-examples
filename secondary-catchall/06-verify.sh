#!/bin/bash
# Verify secondary-catchall: catch-all EgressIP on a secondary host interface.
set -euo pipefail

PASS() { echo -e "\033[32mPASS\033[0m: $1"; }
FAIL() { echo -e "\033[31mFAIL\033[0m: $1"; FAILURES=$((FAILURES+1)); }
FAILURES=0

kubectl wait -n demo-eipt-secondary pod/demo-pod --for=condition=Ready --timeout=60s 2>/dev/null || true

echo "=== EgressIP status ==="
kubectl get egressip eip-default -o jsonpath='{.status}' 2>/dev/null | python3 -m json.tool 2>/dev/null || echo "(no status)"
echo ""

echo "=== Test 1: Traffic to 192.168.250.100 (destination network, via router) ==="
src=$(kubectl exec -n demo-eipt-secondary demo-pod -- curl -s --connect-timeout 5 http://192.168.250.100:8080 2>/dev/null | grep -oP 'client=\K[0-9.]+')
if [ "$src" = "192.168.150.101" ]; then
    PASS "Traffic uses catch-all EgressIP on secondary interface (source: $src)"
else
    FAIL "Expected source 192.168.150.101, got: ${src:-timeout}"
fi

echo ""
echo "=== Node-side state on ovn-worker2 ==="
echo "--- IP rules (priority 6001 = catch-all) ---"
docker exec ovn-worker2 ip rule show | grep -E "600[01]" || echo "(none)"
echo ""
echo "--- EgressIP address on interface ---"
docker exec ovn-worker2 ip -4 addr show | grep "192.168.150.101" || echo "(not found)"
echo ""
echo "--- iptables SNAT rules ---"
docker exec ovn-worker2 iptables -t nat -S OVN-KUBE-EGRESS-IP-MULTI-NIC 2>/dev/null | grep "192.168.150.101" || echo "(none)"

echo ""
if [ $FAILURES -eq 0 ]; then
    echo -e "\033[32mAll tests passed.\033[0m"
else
    echo -e "\033[31m${FAILURES} test(s) failed.\033[0m"
    exit 1
fi
