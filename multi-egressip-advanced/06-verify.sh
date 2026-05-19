#!/bin/bash
# Verify advanced multi-EgressIP example:
#   1. eip-default (catch-all) — all non-matching traffic
#   2. eip-sip (L4 filtered, UDP 5060) — SIP signaling to OAM network
#   3. eip-signaling (CIDR filtered, 2 IPs) — load-balanced to signaling network
set -euo pipefail

NS="demo-eipt-advanced"
POD="demo-pod"

# Wait for pod
kubectl wait -n "${NS}" pod/${POD} --for=condition=Ready --timeout=60s 2>/dev/null || true

echo "=== EgressIP statuses ==="
for eip in eip-default eip-sip eip-signaling; do
    echo "--- ${eip} ---"
    kubectl get egressip ${eip} -o jsonpath='{.status}' 2>/dev/null | python3 -m json.tool 2>/dev/null || echo "(no status)"
    echo ""
done

echo "=== Test 1: Traffic to OAM HTTP (port 8080, NOT matching L4 filter) ==="
echo "Expected: should NOT reach via EgressIP (L4 filter is UDP 5060, not TCP 8080)"
kubectl exec -n ${NS} ${POD} -- curl -s --connect-timeout 5 http://192.168.250.1:8080 2>/dev/null || echo "(timeout — expected, port 8080 not matched by UDP 5060 filter)"
echo ""

echo "=== Test 2: Traffic to signaling network (192.168.200.100:8081, CIDR-matched) ==="
echo "Expected: source should be one of 192.168.200.101 or 192.168.200.201 (EgressIP)"
kubectl exec -n ${NS} ${POD} -- curl -s --connect-timeout 5 http://192.168.200.100:8081
echo ""

echo "=== Test 3: Load balancing verification (20 requests to signaling network) ==="
echo "Expected: both 192.168.200.101 and 192.168.200.201 should appear as source IPs"
declare -A ip_counts
for i in $(seq 1 20); do
    src=$(kubectl exec -n ${NS} ${POD} -- curl -s --connect-timeout 5 http://192.168.200.100:8081 2>/dev/null | grep -oP 'client=\K[0-9.]+')
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
    echo "PASS: Traffic is load-balanced across multiple EgressIPs"
else
    echo "NOTE: Traffic used only one EgressIP (may need more requests or time for OVN to distribute)"
fi
echo ""

echo "=== Node-side state ==="
echo "--- ovn-worker2 IP rules ---"
docker exec ovn-worker2 ip rule show | grep -E "600[01]" || echo "(none)"
echo ""
echo "--- ovn-worker3 IP rules ---"
docker exec ovn-worker3 ip rule show | grep -E "600[01]" || echo "(none)"
echo ""

echo "=== OVN LRP policies ==="
POD_NODE=$(kubectl get pod -n ${NS} ${POD} -o jsonpath='{.spec.nodeName}')
OVNKUBE_POD=$(kubectl get pods -n ovn-kubernetes -l app=ovnkube-node --field-selector spec.nodeName=${POD_NODE} -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n ovn-kubernetes ${OVNKUBE_POD} -c ovnkube-controller -- ovn-nbctl lr-policy-list ovn_cluster_router 2>/dev/null | grep -E " 99 | 100 " | head -10
echo ""
echo "Expected:"
echo "  Priority 100: L4-filtered (udp && udp.dst == 5060) and CIDR-filtered reroutes"
echo "  Priority 99:  Catch-all reroute for eip-default"
