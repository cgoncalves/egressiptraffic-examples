# Secondary Catch-all: EgressIP on secondary host interface

A catch-all EgressIP (no `trafficSelector`) on a secondary host interface. ALL traffic from the pod is routed through the secondary interface and SNATed to the EgressIP address.

- `eip-default`: `192.168.150.101` on secondary host interface — handles all pod traffic

A router container with an internal netns server simulates the destination network on a separate L2 segment.

**Note:** A catch-all EgressIP on a secondary host interface captures ALL pod traffic at the kernel IP rule level (priority 6001). This means the pod cannot reach destinations that are not routable through the secondary interface. In IC mode, coexisting with a trafficSelector EgressIP on the OVN primary network is not supported because the catch-all IP rule intercepts traffic before the OVN gateway router can apply SNAT for the OVN-network EgressIP.

## Setup

```bash
bash 00-setup-infra.sh
bash 02-label-egress-node.sh
kubectl apply -f 01-namespace.yaml
kubectl apply -f 04-egressip.yaml
kubectl apply -f 05-pod.yaml
kubectl wait -n demo-eipt-secondary pod/demo-pod --for=condition=Ready --timeout=60s
```

## Verify

```bash
bash 06-verify.sh
```

- Traffic to `192.168.250.100:8080` should show source `192.168.150.101` (catch-all EgressIP)

## Cleanup

```bash
bash 07-cleanup.sh
```
