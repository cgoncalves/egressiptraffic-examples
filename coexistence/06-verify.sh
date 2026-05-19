#!/bin/bash
# Verify coexistence: trafficSelector EgressIP + default EgressIP on the same pod.
set -euo pipefail

PASS() { echo -e "\033[32mPASS\033[0m: $1"; }
FAIL() { echo -e "\033[31mFAIL\033[0m: $1"; FAILURES=$((FAILURES+1)); }
FAILURES=0

kubectl wait -n demo-eipt-coexist pod/demo-pod --for=condition=Ready --timeout=60s 2>/dev/null || true

echo "=== EgressIP statuses ==="
echo "--- eip-destination (trafficSelector) ---"
kubectl get egressip eip-destination -o jsonpath='{.status}' 2>/dev/null | python3 -m json.tool 2>/dev/null || echo "(no status -- EgressIP not assigned yet)"
echo ""
echo "--- eip-default (catch-all) ---"
kubectl get egressip eip-default -o jsonpath='{.status}' 2>/dev/null | python3 -m json.tool 2>/dev/null || echo "(no status -- EgressIP not assigned yet)"
echo ""

echo "=== Test 1: Traffic to 192.168.250.100 uses trafficSelector EgressIP ==="
src=$(kubectl exec -n demo-eipt-coexist demo-pod -- curl -s --connect-timeout 5 http://192.168.250.100:8080 2>/dev/null | grep -oP 'client=\K[0-9.]+')
if [ "$src" = "192.168.150.101" ]; then
    PASS "Traffic to destination network uses trafficSelector EgressIP (source: $src)"
else
    FAIL "Expected source 192.168.150.101, got: ${src:-timeout}"
fi

echo ""
echo "=== Test 2: OVN LRP priorities ==="
POD_NODE=$(kubectl get pod -n demo-eipt-coexist demo-pod -o jsonpath='{.spec.nodeName}')
OVNKUBE_POD=$(kubectl get pods -n ovn-kubernetes -l app=ovnkube-node --field-selector spec.nodeName=${POD_NODE} -o jsonpath='{.items[0].metadata.name}')
lrps=$(kubectl exec -n ovn-kubernetes ${OVNKUBE_POD} -c ovnkube-controller -- ovn-nbctl lr-policy-list ovn_cluster_router 2>/dev/null | grep -E " 99 | 100 ")
echo "$lrps"
if echo "$lrps" | grep -q " 100 " && echo "$lrps" | grep -q " 99 "; then
    PASS "Both priority 100 (trafficSelector) and 99 (catch-all) LRPs present"
else
    FAIL "Expected LRPs at both priorities 100 and 99"
fi

echo ""
echo "=== Node-side state on ovn-worker2 ==="
echo "--- iptables SNAT rules ---"
docker exec ovn-worker2 iptables -t nat -S OVN-KUBE-EGRESS-IP-MULTI-NIC 2>/dev/null | grep "192.168.150.101" || echo "(none)"

echo ""
echo "NOTE: The default EgressIP (172.18.0.100) SNAT can only be verified for traffic"
echo "leaving the cluster L2 segment. In a kind cluster, all nodes share the same network,"
echo "so intra-cluster traffic bypasses the gateway router where SNAT is applied."

echo ""
if [ $FAILURES -eq 0 ]; then
    echo -e "\033[32mAll tests passed.\033[0m"
else
    echo -e "\033[31m${FAILURES} test(s) failed.\033[0m"
    exit 1
fi
