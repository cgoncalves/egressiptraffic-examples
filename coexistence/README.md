# Coexistence: TrafficSelector EgressIP + default EgressIP

Same pod matched by two EgressIPs:
- `eip-destination` with `trafficSelector`: routes traffic to `192.168.250.0/24` (destination network) via `192.168.150.101` (on link network, priority 100)
- `eip-default` without `trafficSelector`: catches all other traffic via `172.18.0.100` (primary interface, priority 99)

A router container with an internal netns server simulates the destination network on a separate L2 segment. An external server on the kind Docker network (`172.18.0.200`) enables catch-all EgressIP SNAT verification.

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

- Traffic to `192.168.250.100:8080` should show source `192.168.150.101` (trafficSelector EgressIP)
- Traffic to `172.18.0.200:9090` should show source `172.18.0.100` (catch-all EgressIP)
- OVN LRPs should show both priorities: 100 (destination-filtered) and 99 (catch-all)

## Cleanup

```bash
bash 07-cleanup.sh
```
