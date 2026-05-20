#!/bin/bash
# Verify advanced multi-EgressIP example:
#   1. eip-default (catch-all) — all non-matching traffic
#   2. eip-sip (L4 filtered, UDP 5060) — SIP signaling to OAM dest network
#   3. eip-signaling (CIDR filtered, 2 IPs) — load-balanced to signaling dest network
set -euo pipefail

PASS() { echo -e "\033[32mPASS\033[0m: $1"; }
FAIL() { echo -e "\033[31mFAIL\033[0m: $1"; FAILURES=$((FAILURES+1)); }
FAILURES=0

NS="demo-eipt-advanced"
POD="demo-pod"

kubectl wait -n "${NS}" pod/${POD} --for=condition=Ready --timeout=60s 2>/dev/null || true

echo "=== EgressIP statuses ==="
for eip in eip-default eip-sip eip-signaling; do
    echo "--- ${eip} ---"
    kubectl get egressip ${eip} -o jsonpath='{.status}' 2>/dev/null | python3 -m json.tool 2>/dev/null || echo "(no status)"
done
echo ""

echo "=== Test 1: Traffic to signaling dest network (CIDR-matched, via router) ==="
src=$(kubectl exec -n ${NS} ${POD} -- curl -s --connect-timeout 5 http://192.168.251.100:8081 2>/dev/null | grep -oP 'client=\K[0-9.]+')
if [ "$src" = "192.168.200.101" ] || [ "$src" = "192.168.200.201" ]; then
    PASS "Signaling traffic uses EgressIP (source: $src)"
else
    FAIL "Expected source 192.168.200.101 or 192.168.200.201, got: ${src:-timeout}"
fi

echo "=== Test 2: Load balancing (20 requests to signaling dest network) ==="
declare -A ip_counts
for i in $(seq 1 20); do
    src=$(kubectl exec -n ${NS} ${POD} -- curl -s --connect-timeout 5 http://192.168.251.100:8081 2>/dev/null | grep -oP 'client=\K[0-9.]+')
    if [ -n "${src}" ]; then
        ip_counts["${src}"]=$(( ${ip_counts["${src}"]:-0} + 1 ))
    fi
    sleep 0.5
done
echo "Source IP distribution:"
for ip in "${!ip_counts[@]}"; do
    echo "  ${ip}: ${ip_counts[${ip}]} requests"
done
if [ ${#ip_counts[@]} -ge 2 ]; then
    PASS "Traffic is load-balanced across multiple EgressIPs"
else
    FAIL "Traffic used only one EgressIP — expected load balancing across 2 IPs"
fi

echo ""
echo "=== Test 3: OVN LRP priorities ==="
POD_NODE=$(kubectl get pod -n ${NS} ${POD} -o jsonpath='{.spec.nodeName}')
OVNKUBE_POD=$(kubectl get pods -n ovn-kubernetes -l app=ovnkube-node --field-selector spec.nodeName=${POD_NODE} -o jsonpath='{.items[0].metadata.name}')
lrps=$(kubectl exec -n ovn-kubernetes ${OVNKUBE_POD} -c ovnkube-controller -- ovn-nbctl lr-policy-list ovn_cluster_router 2>/dev/null | grep -E " 99 | 100 ")
echo "$lrps"
if echo "$lrps" | grep -q " 100 " && echo "$lrps" | grep -q " 99 "; then
    PASS "Both priority 100 (trafficSelector) and 99 (catch-all) LRPs present"
else
    FAIL "Expected LRPs at both priorities 100 and 99"
fi

echo ""
echo "=== Test 4: Traffic to 172.18.0.200 uses catch-all EgressIP ==="
src=$(kubectl exec -n ${NS} ${POD} -- curl -s --connect-timeout 5 http://172.18.0.200:9090 2>/dev/null | grep -oP 'client=\K[0-9.]+')
if [ "$src" = "172.18.0.100" ]; then
    PASS "Non-matching traffic uses catch-all EgressIP (source: $src)"
else
    FAIL "Expected source 172.18.0.100 (catch-all EgressIP), got: ${src:-timeout}"
fi

echo ""
echo "=== Node-side IP rules ==="
echo "--- ovn-worker2 ---"
docker exec ovn-worker2 ip rule show | grep -E "600[01]" || echo "(none)"
echo "--- ovn-worker3 ---"
docker exec ovn-worker3 ip rule show | grep -E "600[01]" 2>/dev/null || echo "(none)"
echo ""
echo "--- iptables SNAT rules (ovn-worker2) ---"
docker exec ovn-worker2 iptables -t nat -S OVN-KUBE-EGRESS-IP-MULTI-NIC 2>/dev/null | grep -E "192.168.150.101|192.168.200.101" || echo "(none)"

echo ""
if [ $FAILURES -eq 0 ]; then
    echo -e "\033[32mAll tests passed.\033[0m"
else
    echo -e "\033[31m${FAILURES} test(s) failed.\033[0m"
    exit 1
fi
