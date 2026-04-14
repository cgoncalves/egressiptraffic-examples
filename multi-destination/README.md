# Multi-destination: One EgressIP routing to multiple destination networks

A single EgressIPTraffic with two destination CIDRs (`192.168.250.0/24` and `192.168.251.0/24`). Both are routed through the same EgressIP `192.168.150.101` on a secondary host interface.

## Setup

```bash
bash 00-setup-infra.sh
bash 02-label-egress-node.sh
kubectl apply -f 01-namespace.yaml
kubectl apply -f 03-egressiptraffic.yaml
kubectl apply -f 04-egressip.yaml
kubectl apply -f 05-pod.yaml
kubectl wait -n demo-eipt-multi pod/demo-pod --for=condition=Ready --timeout=60s
```

## Verify

```bash
bash 06-verify.sh
```

- Traffic to `192.168.250.1:8080` should show source `192.168.150.101`
- Traffic to `192.168.251.1:8081` should show source `192.168.150.101`
- Traffic to `192.168.150.2:8080` should show the node IP
- The routing table should have destination routes for both CIDRs (no default route)

## Cleanup

```bash
bash 07-cleanup.sh
```
