# Multi-EgressIP: Two trafficSelector EgressIPs on the same pod

Same pod matched by two EgressIPs, each with a different `trafficSelector`:
- `eip-net1`: routes traffic to `192.168.250.0/24` (OAM dest network) via `192.168.150.101` (on OAM link network)
- `eip-net2`: routes traffic to `192.168.251.0/24` (signaling dest network) via `192.168.200.101` (on signaling link network)

Each EgressIP uses a separate pair of link + destination Docker networks with a router container bridging them, simulating a real deployment where external servers are behind gateways. Traffic to non-matching destinations uses normal OVN routing (node IP).

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

- Traffic to `192.168.250.100:8080` should show source `192.168.150.101` (eip-net1)
- Traffic to `192.168.251.100:8081` should show source `192.168.200.101` (eip-net2)
- IP rules at priority 6000 should show two entries with different destination CIDRs

## Cleanup

```bash
bash 07-cleanup.sh
```
