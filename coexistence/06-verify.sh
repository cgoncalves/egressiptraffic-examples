#!/bin/bash
# Verify coexistence: trafficSelector EgressIP + default EgressIP on the same pod.
set -euo pipefail

echo "=== EgressIP statuses ==="
echo "--- eip-destination (trafficSelector) ---"
kubectl get egressip eip-destination -o jsonpath='{.status}' 2>/dev/null | python3 -m json.tool 2>/dev/null || echo "(no status -- EgressIP not assigned yet)"
echo ""
echo "--- eip-default (catch-all) ---"
kubectl get egressip eip-default -o jsonpath='{.status}' 2>/dev/null | python3 -m json.tool 2>/dev/null || echo "(no status -- EgressIP not assigned yet)"
echo ""

echo "=== Test 1: Traffic to 192.168.250.1 (matching trafficSelector destination) ==="
echo "Expected source: 192.168.150.101 (destination-specific EgressIP)"
kubectl exec -n demo-eipt-coexist demo-pod -- curl -s --connect-timeout 5 http://192.168.250.1:8080
echo ""

echo "=== OVN LRP priorities ==="
echo "Priority 100 = trafficSelector (destination-filtered)"
echo "Priority 99  = default (catch-all)"
# Query from the pod's node controller (each node has its own NB DB in IC mode)
POD_NODE=$(kubectl get pod -n demo-eipt-coexist demo-pod -o jsonpath='{.spec.nodeName}')
OVNKUBE_POD=$(kubectl get pods -n ovn-kubernetes -l app=ovnkube-node --field-selector spec.nodeName=${POD_NODE} -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n ovn-kubernetes ${OVNKUBE_POD} -c ovnkube-controller -- ovn-nbctl lr-policy-list ovn_cluster_router 2>/dev/null | grep -E " 99 | 100 "
echo ""
echo "Both priorities should be present: 100 (destination-filtered) reroutes matching traffic,"
echo "99 (catch-all) reroutes everything else via the default EgressIP."
echo ""
echo "NOTE: The default EgressIP (172.18.0.100) SNAT can only be verified for traffic"
echo "leaving the cluster L2 segment. In a kind cluster, all nodes share the same network,"
echo "so intra-cluster traffic bypasses the gateway router where SNAT is applied."
