# Basic: Single destination routing via EgressIPTraffic

Routes pod traffic to `192.168.250.0/24` through EgressIP `192.168.150.101` on a secondary host interface. Traffic to other destinations uses normal OVN routing.

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

- Traffic to `192.168.250.1:8080` should show source `192.168.150.101`
- Traffic to `192.168.150.2:8080` should show the node IP (not the EgressIP)

## Cleanup

```bash
bash 07-cleanup.sh
```
