#!/bin/bash
# Sets up two independent secondary networks on ovn-worker2, each with its own
# veth pair and router, simulating two separate external networks.
#
# Network layout on ovn-worker2:
#
#   ovn-worker2 host                          oam netns (OAM router)
#   +--------------------------+              +----------------------------+
#   | oam-host: 192.168.150.10 |<---veth----->| oam-ns: 192.168.150.1     |
#   | route: 192.168.250.0/24  |              | oam-ext: 192.168.250.1/32  |
#   |   via 192.168.150.1      |              | HTTP :8080                 |
#   +--------------------------+              +----------------------------+
#
#   +--------------------------+              signaling netns (SIG router)
#   | sig-host: 192.168.200.10 |              +----------------------------+
#   | route: 192.168.251.0/24  |<---veth----->| sig-ns: 192.168.200.1      |
#   |   via 192.168.200.1      |              | sig-ext: 192.168.251.1/32  |
#   +--------------------------+              | HTTP :8081                  |
#                                             +----------------------------+

set -euo pipefail

EGRESS_NODE="ovn-worker2"

echo "=== Installing tools on worker nodes ==="
for node in ovn-worker ovn-worker2; do
    docker exec "${node}" bash -c "apt-get update -qq && apt-get install -y -qq tcpdump curl python3 > /dev/null 2>&1"
done

echo "=== Cleaning up previous state on ${EGRESS_NODE} ==="
for ns in oam signaling; do
    docker exec "${EGRESS_NODE}" ip netns del ${ns} 2>/dev/null || true
done
docker exec "${EGRESS_NODE}" ip link del oam-host 2>/dev/null || true
docker exec "${EGRESS_NODE}" ip link del sig-host 2>/dev/null || true

# Write HTTP listener script
docker exec "${EGRESS_NODE}" bash -c 'cat > /tmp/http-listener.py << '\''PYEOF'\''
import http.server, socketserver, sys
port = int(sys.argv[1])
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(("client=" + self.client_address[0] + "\n").encode())
    def log_message(self, fmt, *args):
        pass
with socketserver.TCPServer(("", port), H) as s:
    s.serve_forever()
PYEOF'

setup_netns() {
    local ns=$1 veth_host=$2 veth_ns=$3 host_ip=$4 router_ip=$5 dummy_name=$6 dummy_ip=$7 subnet=$8

    echo "=== Creating network namespace ${ns} ==="
    docker exec "${EGRESS_NODE}" ip netns add ${ns}
    docker exec "${EGRESS_NODE}" ip link add ${veth_host} type veth peer name ${veth_ns}
    docker exec "${EGRESS_NODE}" ip link set ${veth_ns} netns ${ns}

    # Host side (node's secondary NIC)
    docker exec "${EGRESS_NODE}" ip addr add ${host_ip}/24 dev ${veth_host}
    docker exec "${EGRESS_NODE}" ip link set ${veth_host} up
    docker exec "${EGRESS_NODE}" ip route add ${subnet} via ${router_ip} dev ${veth_host}

    # Netns side (external router)
    docker exec "${EGRESS_NODE}" ip netns exec ${ns} ip addr add ${router_ip}/24 dev ${veth_ns}
    docker exec "${EGRESS_NODE}" ip netns exec ${ns} ip link set ${veth_ns} up
    docker exec "${EGRESS_NODE}" ip netns exec ${ns} ip link set lo up
    docker exec "${EGRESS_NODE}" ip netns exec ${ns} sysctl -w net.ipv4.ip_forward=1 > /dev/null

    # External network behind the router
    docker exec "${EGRESS_NODE}" ip netns exec ${ns} ip link add ${dummy_name} type dummy
    docker exec "${EGRESS_NODE}" ip netns exec ${ns} ip link set ${dummy_name} up
    docker exec "${EGRESS_NODE}" ip netns exec ${ns} ip addr add ${dummy_ip}/32 dev ${dummy_name}
    docker exec "${EGRESS_NODE}" ip netns exec ${ns} ip route add ${subnet} dev ${dummy_name}

}

#              ns         veth_host  veth_ns  host_ip         router_ip       dummy     dummy_ip       subnet
setup_netns    oam        oam-host   oam-ns   192.168.150.10  192.168.150.1   oam-ext   192.168.250.1  192.168.250.0/24
setup_netns    signaling  sig-host   sig-ns   192.168.200.10  192.168.200.1   sig-ext   192.168.251.1  192.168.251.0/24

# Start HTTP listeners after all namespaces are created.
# Using "docker exec -d" with nsenter (not "ip netns exec") for reliable backgrounding.
start_listener() {
    local ns=$1 port=$2
    docker exec "${EGRESS_NODE}" bash -c "nsenter --net=/var/run/netns/${ns} pkill -f 'python3 /tmp/http-listener.py ${port}' 2>/dev/null" || true
    docker exec -d "${EGRESS_NODE}" nsenter --net=/var/run/netns/${ns} python3 /tmp/http-listener.py ${port}
}
start_listener oam 8080
start_listener signaling 8081
sleep 1
docker exec "${EGRESS_NODE}" ip netns exec oam ss -tlnp | grep -q ":8080" || echo "WARNING: listener on port 8080 in oam failed to start"
docker exec "${EGRESS_NODE}" ip netns exec signaling ss -tlnp | grep -q ":8081" || echo "WARNING: listener on port 8081 in signaling failed to start"

echo "=== Done ==="
echo "OAM:       192.168.250.1:8080 (EgressIP 192.168.150.101 via router 192.168.150.1)"
echo "Signaling: 192.168.251.1:8081 (EgressIP 192.168.200.101 via router 192.168.200.1)"
