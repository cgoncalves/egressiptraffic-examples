# Multi-destination: One EgressIP routing to multiple destinations

A single EgressIPTraffic with two destination host CIDRs (`192.168.150.100/32` and `192.168.150.200/32`). Both are routed through the same EgressIP `192.168.150.101` on the OAM Docker network.

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

- Traffic to `192.168.150.100:8080` should show source `192.168.150.101`
- Traffic to `192.168.150.200:8081` should show source `192.168.150.101`
- IP rules should show both `/32` destination entries

## Cleanup

```bash
bash 07-cleanup.sh
```
