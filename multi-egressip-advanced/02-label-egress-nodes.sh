#!/bin/bash
# Label both worker nodes as egress-assignable.
# ovn-worker is the pod node and must NOT be labeled.
set -euo pipefail

if ! kubectl get node ovn-worker3 &>/dev/null; then
    echo "ERROR: ovn-worker3 does not exist. This example requires 3 worker nodes."
    exit 1
fi

kubectl label node ovn-worker2 k8s.ovn.org/egress-assignable="" --overwrite
kubectl label node ovn-worker3 k8s.ovn.org/egress-assignable="" --overwrite
