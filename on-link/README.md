# On-link: Destination on the same L2 as EgressIP interface

Validates that EgressIP SNAT works when the destination is directly attached to the EgressIP interface (same L2 segment, no router). The pod's traffic to `192.168.150.200` should appear with source `192.168.150.101` (the EgressIP), not the node's own link address.

## Setup

```bash
bash 00-setup-infra.sh
bash 02-label-egress-node.sh
kubectl apply -f 01-namespace.yaml
kubectl apply -f 03-egressiptraffic.yaml
kubectl apply -f 04-egressip.yaml
kubectl apply -f 05-pod.yaml
kubectl wait -n demo-eipt pod/demo-pod --for=condition=Ready --timeout=60s
```

## Verify

```bash
bash 06-verify.sh
```

- Traffic to `192.168.150.200:8080` should show source `192.168.150.101` (EgressIP SNAT)

## Cleanup

```bash
bash 07-cleanup.sh
```
