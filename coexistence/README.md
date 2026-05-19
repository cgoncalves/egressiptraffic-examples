# Coexistence: TrafficSelector EgressIP + default EgressIP

Same pod matched by two EgressIPs:
- `eip-destination` with `trafficSelector`: routes traffic to `192.168.150.0/24` via `192.168.150.101` (oam-net, priority 100)
- `eip-default` without `trafficSelector`: catches all other traffic via `172.18.0.100` (primary interface, priority 99)

This demonstrates the priority-based coexistence: destination-specific rules (priority 100) are evaluated before the catch-all (priority 99).

## Setup

```bash
bash 00-setup-infra.sh
bash 02-label-egress-node.sh
kubectl apply -f 01-namespace.yaml
kubectl apply -f 03-egressiptraffic.yaml
kubectl apply -f 04-egressip.yaml
kubectl apply -f 05-pod.yaml
kubectl wait -n demo-eipt-coexist pod/demo-pod --for=condition=Ready --timeout=60s
```

## Verify

```bash
bash 06-verify.sh
```

- Traffic to `192.168.150.100:8080` should show source `192.168.150.101` (trafficSelector EgressIP)
- OVN LRPs should show both priorities: 100 (destination-filtered) and 99 (catch-all)

Note: The default EgressIP SNAT (`172.18.0.100`) can only be verified for traffic leaving the cluster's L2 segment. In a kind cluster, all nodes share the same network, so intra-cluster traffic bypasses the gateway router where SNAT is applied.

## Cleanup

```bash
bash 07-cleanup.sh
```
