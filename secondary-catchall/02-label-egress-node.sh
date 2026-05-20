#!/bin/bash
kubectl label node ovn-worker2 k8s.ovn.org/egress-assignable="" --overwrite
