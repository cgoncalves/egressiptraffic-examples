# Advanced Multi-EgressIP: Catch-all + L4-filtered + load-balanced CIDR-filtered

A single pod served by three EgressIPs demonstrating the full feature set:

1. **`eip-default`** (no trafficSelector): catch-all at priority 99 for all non-matching traffic via `172.18.0.100` on the primary network
2. **`eip-sip`** (L4-filtered trafficSelector): UDP port 5060 (SIP signaling) to `192.168.250.0/24` via `192.168.150.101` on ovn-worker2's OAM interface
3. **`eip-signaling`** (CIDR-filtered trafficSelector, 2 IPs): all traffic to `192.168.200.0/24` load-balanced across `192.168.200.101` (ovn-worker2) and `192.168.200.201` (ovn-worker3) via a shared Docker signaling network

The pod runs on `ovn-worker` (not an egress node). Both `ovn-worker2` and `ovn-worker3` are egress-assignable.

## Prerequisites

- Kind cluster with **3 worker nodes** (ovn-worker, ovn-worker2, ovn-worker3)
- `eipt-implementation-l4-matching` branch deployed with `--enable-egress-iptraffic=true`
- Docker available on the host (for the signaling network)

## Setup

```bash
bash 00-setup-infra.sh
bash 02-label-egress-nodes.sh
kubectl apply -f 01-namespace.yaml
kubectl apply -f 03-egressiptraffic.yaml
kubectl apply -f 04-egressip.yaml
kubectl apply -f 05-pod.yaml
kubectl wait -n demo-eipt-advanced pod/demo-pod --for=condition=Ready --timeout=60s
```

## Verify

```bash
bash 06-verify.sh
```

- Traffic to OAM network on TCP 8080 should NOT use EgressIP (L4 filter is UDP 5060)
- Traffic to signaling network should use EgressIP (CIDR-matched)
- Load balancing: repeated requests to signaling network should show both `192.168.200.101` and `192.168.200.201` as source IPs
- OVN LRPs at priority 100 (both L4-filtered and CIDR-filtered, non-overlapping destinations) and priority 99 (catch-all for all other traffic)

## Cleanup

```bash
bash 07-cleanup.sh
```
