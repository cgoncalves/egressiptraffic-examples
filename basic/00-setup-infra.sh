#!/bin/bash
# Sets up secondary network infrastructure on ovn-worker2 (the egress node).
# Creates a network namespace acting as an external router, reachable via a
# secondary host interface, with an HTTP listener for source IP verification.
#
# Network layout on ovn-worker2:
#
#   ovn-worker2 host                          oam netns (external router)
#   +--------------------------+              +----------------------------+
#   | oam-host: 192.168.150.10 |<---veth----->| oam-ns: 192.168.150.1     |
#   |                          |              | oam-ext: 192.168.250.1/32  |
#   | route: 192.168.250.0/24  |              | (IP forwarding enabled)    |
#   |   via 192.168.150.1      |              | HTTP listener :8080        |
#   +--------------------------+              +----------------------------+
#
# The EgressIP (192.168.150.101/24) will be assigned to oam-host.
# Traffic to 192.168.250.0/24 will be routed via gateway 192.168.150.1.

set -euo pipefail

EGRESS_NODE="ovn-worker2"

echo "=== Installing tools on worker nodes ==="
for node in ovn-worker ovn-worker2; do
    docker exec "${node}" bash -c "apt-get update -qq && apt-get install -y -qq tcpdump curl python3 > /dev/null 2>&1"
done

echo "=== Cleaning up previous state on ${EGRESS_NODE} ==="
docker exec "${EGRESS_NODE}" ip netns del oam 2>/dev/null || true
docker exec "${EGRESS_NODE}" ip link del oam-host 2>/dev/null || true

echo "=== Creating network namespace oam on ${EGRESS_NODE} ==="
docker exec "${EGRESS_NODE}" ip netns add oam
docker exec "${EGRESS_NODE}" ip link add oam-host type veth peer name oam-ns
docker exec "${EGRESS_NODE}" ip link set oam-ns netns oam

# Host side (the node's secondary NIC)
docker exec "${EGRESS_NODE}" ip addr add 192.168.150.10/24 dev oam-host
docker exec "${EGRESS_NODE}" ip link set oam-host up
# Route to the external network via the router (as a real network admin would configure)
docker exec "${EGRESS_NODE}" ip route add 192.168.250.0/24 via 192.168.150.1 dev oam-host

# Netns side (acts as the external router at 192.168.150.1)
docker exec "${EGRESS_NODE}" ip netns exec oam ip addr add 192.168.150.1/24 dev oam-ns
docker exec "${EGRESS_NODE}" ip netns exec oam ip link set oam-ns up
docker exec "${EGRESS_NODE}" ip netns exec oam ip link set lo up
docker exec "${EGRESS_NODE}" ip netns exec oam sysctl -w net.ipv4.ip_forward=1 > /dev/null

# Dummy interface simulating an external network behind the router (192.168.250.0/24)
docker exec "${EGRESS_NODE}" ip netns exec oam ip link add oam-ext type dummy
docker exec "${EGRESS_NODE}" ip netns exec oam ip link set oam-ext up
docker exec "${EGRESS_NODE}" ip netns exec oam ip addr add 192.168.250.1/32 dev oam-ext
docker exec "${EGRESS_NODE}" ip netns exec oam ip route add 192.168.250.0/24 dev oam-ext

# Write HTTP listener script and start it in the background
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

docker exec "${EGRESS_NODE}" bash -c "nsenter --net=/var/run/netns/oam pkill -f 'python3 /tmp/http-listener.py 8080' 2>/dev/null" || true
docker exec -d "${EGRESS_NODE}" nsenter --net=/var/run/netns/oam python3 /tmp/http-listener.py 8080
sleep 1
docker exec "${EGRESS_NODE}" ip netns exec oam ss -tlnp | grep -q ":8080" || echo "WARNING: listener on port 8080 in oam failed to start"

echo "=== Done ==="
echo "Router (oam netns):  192.168.150.1"
echo "Node NIC (oam-host): 192.168.150.10"
echo "EgressIP:            192.168.150.101 (assigned to oam-host)"
echo "External network:    192.168.250.0/24 (via router, HTTP on :8080)"
