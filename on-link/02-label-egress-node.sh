#!/bin/bash
# Label ovn-worker2 as egress-assignable so EgressIPs can be hosted there.
kubectl label node ovn-worker2 k8s.ovn.org/egress-assignable="" --overwrite
