# L4 Filtering: Per-protocol/port EgressIP routing

Routes only specific protocol/port traffic via the EgressIP. Traffic to the same destination CIDR on non-matching ports uses normal OVN routing.

This example configures:
- **TCP 8080** (HTTP) to `192.168.150.0/24` via EgressIP `192.168.150.101`
- All other traffic to `192.168.150.0/24` is **not** routed via the EgressIP

## Prerequisites

Requires the `eipt-implementation-l4-matching` branch of ovn-kubernetes which adds `trafficMatchers` with protocol/port fields to the EgressIPTraffic CRD.

## Setup

```bash
bash 00-setup-infra.sh
bash 02-label-egress-node.sh
kubectl apply -f 01-namespace.yaml
kubectl apply -f 03-egressiptraffic.yaml
kubectl apply -f 04-egressip.yaml
kubectl apply -f 05-pod.yaml
kubectl wait -n demo-eipt-l4 pod/demo-pod --for=condition=Ready --timeout=60s
```

## Verify

```bash
bash 06-verify.sh
```

- TCP to `192.168.150.100:8080` should be routed via EgressIP (source `192.168.150.101`)
- IP rules should show `ipproto 6 dport 8080`
- OVN LRP match should include `tcp && tcp.dst == 8080`

## Cleanup

```bash
bash 07-cleanup.sh
```
