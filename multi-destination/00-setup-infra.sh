#!/bin/bash
# Sets up secondary network infrastructure on ovn-worker2 with two external
# networks behind the same router, reachable via one secondary host interface.
#
# Network layout on ovn-worker2:
#
#   ovn-worker2 host                          oam netns (external router)
#   +--------------------------+              +------------------------------+
#   | oam-host: 192.168.150.10 |<---veth----->| oam-ns: 192.168.150.1       |
#   |                          |              | oam-ext: 192.168.250.1/32    |
#   | routes: 192.168.250.0/24 |              | oam-ext2: 192.168.251.1/32   |
#   |   and .251.0/24 via .1   |              | (IP forwarding enabled)      |
#   +--------------------------+              | HTTP :8080 (oam-ext)         |
#                                             | HTTP :8081 (oam-ext2)        |
#                                             +------------------------------+

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
# Routes to the external networks via the router
docker exec "${EGRESS_NODE}" ip route add 192.168.250.0/24 via 192.168.150.1 dev oam-host
docker exec "${EGRESS_NODE}" ip route add 192.168.251.0/24 via 192.168.150.1 dev oam-host

# Netns side (acts as the external router)
docker exec "${EGRESS_NODE}" ip netns exec oam ip addr add 192.168.150.1/24 dev oam-ns
docker exec "${EGRESS_NODE}" ip netns exec oam ip link set oam-ns up
docker exec "${EGRESS_NODE}" ip netns exec oam ip link set lo up
docker exec "${EGRESS_NODE}" ip netns exec oam sysctl -w net.ipv4.ip_forward=1 > /dev/null

# Two dummy interfaces simulating two external networks behind the router
docker exec "${EGRESS_NODE}" ip netns exec oam ip link add oam-ext type dummy
docker exec "${EGRESS_NODE}" ip netns exec oam ip link set oam-ext up
docker exec "${EGRESS_NODE}" ip netns exec oam ip addr add 192.168.250.1/32 dev oam-ext
docker exec "${EGRESS_NODE}" ip netns exec oam ip route add 192.168.250.0/24 dev oam-ext

docker exec "${EGRESS_NODE}" ip netns exec oam ip link add oam-ext2 type dummy
docker exec "${EGRESS_NODE}" ip netns exec oam ip link set oam-ext2 up
docker exec "${EGRESS_NODE}" ip netns exec oam ip addr add 192.168.251.1/32 dev oam-ext2
docker exec "${EGRESS_NODE}" ip netns exec oam ip route add 192.168.251.0/24 dev oam-ext2

# Write HTTP listener script and start listeners
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

docker exec "${EGRESS_NODE}" bash -c "nsenter --net=/var/run/netns/oam pkill -f 'python3 /tmp/http-listener.py' 2>/dev/null" || true
docker exec -d "${EGRESS_NODE}" nsenter --net=/var/run/netns/oam python3 /tmp/http-listener.py 8080
docker exec -d "${EGRESS_NODE}" nsenter --net=/var/run/netns/oam python3 /tmp/http-listener.py 8081
sleep 1
docker exec "${EGRESS_NODE}" ip netns exec oam ss -tlnp | grep -q ":8080" || echo "WARNING: listener on port 8080 failed to start"
docker exec "${EGRESS_NODE}" ip netns exec oam ss -tlnp | grep -q ":8081" || echo "WARNING: listener on port 8081 failed to start"

echo "=== Done ==="
echo "External network 1: 192.168.250.0/24 (HTTP on :8080)"
echo "External network 2: 192.168.251.0/24 (HTTP on :8081)"
