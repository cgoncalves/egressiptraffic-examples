# Multi-EgressIP: Two trafficSelector EgressIPs on the same pod

Same pod matched by two EgressIPs, each with a different `trafficSelector`:
- `eip-net1`: routes traffic to `192.168.150.0/24` via `192.168.150.101` (oam-net)
- `eip-net2`: routes traffic to `192.168.200.0/24` via `192.168.200.101` (sig-net)

Each EgressIP uses a different Docker network with its own routing table and IP rules. Traffic to non-matching destinations uses normal OVN routing (node IP).

## Setup

```bash
bash 00-setup-infra.sh
bash 02-label-egress-node.sh
kubectl apply -f 01-namespace.yaml
kubectl apply -f 03-egressiptraffic.yaml
kubectl apply -f 04-egressip.yaml
kubectl apply -f 05-pod.yaml
kubectl wait -n demo-eipt-multi-eip pod/demo-pod --for=condition=Ready --timeout=60s
```

## Verify

```bash
bash 06-verify.sh
```

- Traffic to `192.168.150.100:8080` should show source `192.168.150.101` (eip-net1)
- Traffic to `192.168.200.100:8081` should show source `192.168.200.101` (eip-net2)
- IP rules at priority 6000 should show two entries with different destination CIDRs

## Cleanup

```bash
bash 07-cleanup.sh
```
