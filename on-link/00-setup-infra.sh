#!/bin/bash
# Sets up a Docker link network with a destination server directly on the
# same L2 segment as the EgressIP interface (no router needed).
#
# Network layout:
#
#   ovn-worker2 (egress node)              oam-server container
#   +---------------------------+         +------------------------------+
#   | oam-link-net:             |         | eth0: 192.168.150.200        |
#   |   192.168.150.x/24        |<-link-->| HTTP :8080                   |
#   | EgressIP:                 |         +------------------------------+
#   |   192.168.150.101/32      |
#   +---------------------------+
#
#   oam-link-net: 192.168.150.0/24 (Docker network)
#   Destination:  192.168.150.200  (same L2 as EgressIP, on-link)

set -euo pipefail

EGRESS_NODE="ovn-worker2"

echo "=== Cleaning up previous state ==="
docker rm -f oam-server 2>/dev/null || true
docker network disconnect oam-link-net "${EGRESS_NODE}" 2>/dev/null || true
docker network rm oam-link-net 2>/dev/null || true

echo "=== Creating Docker link network ==="
docker network create oam-link-net --subnet=192.168.150.0/24 --gateway=192.168.150.254

echo "=== Starting destination server on link network ==="
docker run -d --name oam-server --network oam-link-net --ip 192.168.150.200 \
    --privileged registry.access.redhat.com/ubi9/ubi \
    bash -c '
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
        python3 /tmp/http-listener.py 8080
    '

echo "=== Connecting egress node to link network ==="
docker network connect oam-link-net "${EGRESS_NODE}"

sleep 3
echo "=== Verifying ==="
docker exec oam-server curl -s --connect-timeout 2 http://127.0.0.1:8080 || echo "WARNING: server not responding"

NODE_LINK_IP=$(docker exec "${EGRESS_NODE}" ip -4 addr show | grep "192.168.150\." | grep -v 254 | awk '{print $2}' | cut -d/ -f1 | head -1)
echo "=== Done ==="
echo "Link network:   192.168.150.0/24 (Docker, egress node: ${NODE_LINK_IP})"
echo "Server:         192.168.150.200 (oam-server container, same L2)"
echo "EgressIP:       192.168.150.101"
