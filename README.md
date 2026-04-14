# EgressIPTraffic Examples

Example use cases for the **EgressIPTraffic** feature in [ovn-kubernetes](https://github.com/ovn-kubernetes/ovn-kubernetes), which enables per-destination egress IP routing via a `trafficSelector` on EgressIP and a new `EgressIPTraffic` CRD.

## Upstream References

- **OKEP**: [OKEP-6227: EgressIPTraffic — Per-Destination Egress IP Routing](https://github.com/ovn-kubernetes/ovn-kubernetes/pull/6226)
- **Implementation PR**: [ovn-kubernetes/ovn-kubernetes#6237](https://github.com/ovn-kubernetes/ovn-kubernetes/pull/6237)

## Use Cases

| Directory | Description |
|-----------|-------------|
| [basic/](basic/) | Single EgressIP with `trafficSelector` routing traffic to one destination network via a secondary host interface |
| [multi-destination/](multi-destination/) | One EgressIP routing to multiple destination CIDRs defined in a single EgressIPTraffic |
| [coexistence/](coexistence/) | TrafficSelector EgressIP (priority 100) coexisting with a default EgressIP (priority 99) on the same pod |
| [multi-egressip/](multi-egressip/) | Two trafficSelector EgressIPs on the same pod, each routing to different destination networks via different interfaces |

## Prerequisites

- A kind cluster with ovn-kubernetes deployed from the `eipt-implementation` branch (or any build that includes the EgressIPTraffic feature)
- `--enable-egress-iptraffic=true` flag enabled
- `kubectl` configured to access the cluster

## Usage

Each use case is self-contained. Run them one at a time — clean up before switching:

```bash
cd <use-case>/
bash 00-setup-infra.sh
bash 02-label-egress-node.sh
kubectl apply -f 01-namespace.yaml
kubectl apply -f 03-egressiptraffic.yaml -f 04-egressip.yaml -f 05-pod.yaml
kubectl wait -n <namespace> pod/demo-pod --for=condition=Ready --timeout=60s
bash 06-verify.sh
bash 07-cleanup.sh
```

The use cases share EgressIP addresses, so only one can be active at a time.
