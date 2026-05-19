#!/bin/bash
# Verify multi-EgressIP use case: two trafficSelector EgressIPs on the same pod.
set -euo pipefail

PASS() { echo -e "\033[32mPASS\033[0m: $1"; }
FAIL() { echo -e "\033[31mFAIL\033[0m: $1"; FAILURES=$((FAILURES+1)); }
FAILURES=0

kubectl wait -n demo-eipt-multi-eip pod/demo-pod --for=condition=Ready --timeout=60s 2>/dev/null || true

echo "=== EgressIP statuses ==="
for eip in eip-net1 eip-net2; do
    echo "--- ${eip} ---"
    kubectl get egressip ${eip} -o jsonpath='{.status}' 2>/dev/null | python3 -m json.tool 2>/dev/null || echo "(no status)"
done
echo ""

echo "=== Test 1: Traffic to 192.168.250.100 (OAM, via router) ==="
src=$(kubectl exec -n demo-eipt-multi-eip demo-pod -- curl -s --connect-timeout 5 http://192.168.250.100:8080 2>/dev/null | grep -oP 'client=\K[0-9.]+')
if [ "$src" = "192.168.150.101" ]; then
    PASS "OAM traffic uses eip-net1 (source: $src)"
else
    FAIL "Expected source 192.168.150.101, got: ${src:-timeout}"
fi

echo "=== Test 2: Traffic to 192.168.251.100 (signaling, via router) ==="
src=$(kubectl exec -n demo-eipt-multi-eip demo-pod -- curl -s --connect-timeout 5 http://192.168.251.100:8081 2>/dev/null | grep -oP 'client=\K[0-9.]+')
if [ "$src" = "192.168.200.101" ]; then
    PASS "Signaling traffic uses eip-net2 (source: $src)"
else
    FAIL "Expected source 192.168.200.101, got: ${src:-timeout}"
fi

echo ""
echo "=== Node-side state on ovn-worker2 ==="
echo "--- IP rules ---"
docker exec ovn-worker2 ip rule show | grep "6000" || echo "(none)"
echo ""
echo "--- EgressIP addresses on interfaces ---"
docker exec ovn-worker2 ip -4 addr show | grep -E "192.168.150.101|192.168.200.101" || echo "(not found)"
echo ""
echo "--- iptables SNAT rules ---"
docker exec ovn-worker2 iptables -t nat -S OVN-KUBE-EGRESS-IP-MULTI-NIC 2>/dev/null | grep -E "192.168.150.101|192.168.200.101" || echo "(none)"

echo ""
if [ $FAILURES -eq 0 ]; then
    echo -e "\033[32mAll tests passed.\033[0m"
else
    echo -e "\033[31m${FAILURES} test(s) failed.\033[0m"
    exit 1
fi
