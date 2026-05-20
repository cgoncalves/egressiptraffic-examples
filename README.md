# EgressIPTraffic Examples

Example use cases for the **EgressIPTraffic** feature in [ovn-kubernetes](https://github.com/ovn-kubernetes/ovn-kubernetes), which enables per-destination egress IP routing with optional L4 protocol/port filtering via a `trafficSelector` on EgressIP and a new `EgressIPTraffic` CRD with `trafficMatchers`.

## Upstream References

- **OKEP**: [OKEP-6227: Support per-destination egress IP routing](https://github.com/ovn-kubernetes/ovn-kubernetes/pull/6228)
- **Implementation PR**: [ovn-kubernetes/ovn-kubernetes#6237](https://github.com/ovn-kubernetes/ovn-kubernetes/pull/6237)

## Use Cases

| Directory | Description |
|-----------|-------------|
| [basic/](basic/) | Single EgressIP with `trafficSelector` routing traffic to one destination network via a secondary host interface |
| [multi-destination/](multi-destination/) | One EgressIP routing to multiple destination CIDRs defined in a single EgressIPTraffic |
| [coexistence/](coexistence/) | TrafficSelector EgressIP (priority 100) coexisting with a catch-all EgressIP (priority 99) on the same pod, with catch-all SNAT verification |
| [multi-egressip/](multi-egressip/) | Two trafficSelector EgressIPs on the same pod, each routing to different destination networks via different interfaces |
| [l4-filtering/](l4-filtering/) | L4 protocol/port filtering: only TCP traffic on a specific port uses the EgressIP |
| [multi-egressip-advanced/](multi-egressip-advanced/) | Three coexisting EgressIPs: catch-all + L4-filtered + CIDR-filtered with load balancing across two egress nodes (requires 3 worker nodes) |
| [on-link/](on-link/) | Destination on the same L2 as the EgressIP interface — validates SNAT works for on-link traffic |
| [secondary-catchall/](secondary-catchall/) | Catch-all EgressIP on a secondary host interface routing all pod traffic |

## Prerequisites

- A kind cluster with ovn-kubernetes deployed from the `eipt-implementation-l4-matching` branch
- `--enable-egress-iptraffic=true` flag enabled
- `kubectl` configured to access the cluster
- `multi-egressip-advanced/` requires 3 worker nodes

## Usage

Each use case is self-contained. Run them one at a time — clean up before switching:

```bash
cd <use-case>/
bash 00-setup-infra.sh
bash 02-label-egress-node.sh
kubectl apply -f 01-namespace.yaml
kubectl apply -f 03-egressiptraffic.yaml -f 04-egressip.yaml -f 05-pod.yaml  # some examples omit 03
kubectl wait -n <namespace> pod/demo-pod --for=condition=Ready --timeout=60s
bash 06-verify.sh
bash 07-cleanup.sh
```

The use cases share EgressIP addresses, so only one can be active at a time.

## Infrastructure Pattern

Most examples use Docker link networks for EgressIP interfaces and router containers with internal netns-based destination servers on separate L2 segments. This simulates real deployments where external servers are behind gateways. The `on-link/` example is the exception — it places the destination server directly on the link network to validate SNAT for on-link traffic.
