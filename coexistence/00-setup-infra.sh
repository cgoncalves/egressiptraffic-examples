#!/bin/bash
# Sets up a Docker link network and a router container with an internal
# netns-based destination server.
#
# Network layout:
#
#   ovn-worker2 (egress node)              oam-router container
#   +---------------------------+         +------------------------------+
#   | oam-link-net:             |         | eth0: 192.168.150.1          |
#   |   192.168.150.x/24        |<-link-->| IP forwarding enabled        |
#   | EgressIP (traffic):       |         |                              |
#   |   192.168.150.101/32      |         | veth-host: 192.168.250.1/24  |
#   | EgressIP (catch-all):     |         |   |                          |
#   |   172.18.0.100/32         |         |   v (veth pair)              |
#   +---------------------------+         | netns: oam-server            |
#                                         |   veth-ns: 192.168.250.100  |
#                                         |   HTTP :8080                 |
#                                         +------------------------------+
#
#   oam-link-net: 192.168.150.0/24 (Docker network)
#   Destination:  192.168.250.0/24 (inside router container, different L2)
#
# Two EgressIPs on the same pod:
# - eip-destination (trafficSelector): 192.168.150.101 for dest-net traffic
# - eip-default (catch-all): 172.18.0.100 on primary network

set -euo pipefail

EGRESS_NODE="ovn-worker2"

echo "=== Cleaning up previous state ==="
docker rm -f oam-router ext-server 2>/dev/null || true
docker network disconnect oam-link-net "${EGRESS_NODE}" 2>/dev/null || true
docker network rm oam-link-net 2>/dev/null || true

echo "=== Creating Docker link network ==="
docker network create oam-link-net --subnet=192.168.150.0/24 --gateway=192.168.150.254

echo "=== Starting router container with internal server ==="
docker run -d --name oam-router --network oam-link-net --ip 192.168.150.1 \
    --privileged registry.access.redhat.com/ubi9/ubi \
    bash -c '
        echo 1 > /proc/sys/net/ipv4/ip_forward

        # Create server netns with veth pair
        ip netns add oam-server
        ip link add veth-host type veth peer name veth-ns
        ip link set veth-ns netns oam-server

        ip addr add 192.168.250.1/24 dev veth-host
        ip link set veth-host up

        ip netns exec oam-server ip addr add 192.168.250.100/24 dev veth-ns
        ip netns exec oam-server ip link set veth-ns up
        ip netns exec oam-server ip link set lo up
        ip netns exec oam-server ip route add default via 192.168.250.1

        # Start HTTP listener in server netns
        cat > /tmp/http-listener.py << PYEOF
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
PYEOF
        nsenter --net=/var/run/netns/oam-server python3 /tmp/http-listener.py 8080 &

        sleep infinity
    '

echo "=== Starting external server on kind network (for catch-all EgressIP verification) ==="
# This server is on the kind Docker network (172.18.0.0/16) at a free IP.
# Traffic from the pod to this server does NOT match the trafficSelector EgressIP,
# so it uses the catch-all EgressIP (172.18.0.100) via the OVN gateway router.
KINDNET=$(docker network ls --filter name=kind --format '{{.Name}}')
docker run -d --name ext-server --network "${KINDNET}" --ip 172.18.0.200 \
    registry.access.redhat.com/ubi9/ubi python3 -c "
import http.server, socketserver
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain')
        self.end_headers()
        self.wfile.write(('client=' + self.client_address[0] + '\n').encode())
    def log_message(self, fmt, *args):
        pass
with socketserver.TCPServer(('', 9090), H) as s:
    s.serve_forever()
"

echo "=== Connecting egress node to link network ==="
docker network connect oam-link-net "${EGRESS_NODE}"
docker exec "${EGRESS_NODE}" ip route add 192.168.250.0/24 via 192.168.150.1 2>/dev/null || true

sleep 3
echo "=== Verifying ==="
docker exec oam-router curl -s --connect-timeout 2 http://192.168.250.100:8080 || echo "WARNING: router cannot reach server"

NODE_LINK_IP=$(docker exec "${EGRESS_NODE}" ip -4 addr show | grep "192.168.150\." | grep -v 254 | awk '{print $2}' | cut -d/ -f1 | head -1)
echo "=== Done ==="
echo "Link network:   192.168.150.0/24 (Docker, egress node: ${NODE_LINK_IP})"
echo "Router:         192.168.150.1 (oam-router container)"
echo "Dest network:   192.168.250.0/24 (netns inside oam-router, server: 192.168.250.100:8080)"
echo "EgressIP (trafficSelector): 192.168.150.101"
echo "EgressIP (catch-all):       172.18.0.100"
echo "External server:  172.18.0.200:9090 (on kind network, for catch-all verification)"
