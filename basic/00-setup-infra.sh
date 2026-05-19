#!/bin/bash
# Sets up a Docker network and external server container for the basic example.
#
# Network layout:
#
#   ovn-worker (pod node)
#
#   ovn-worker2 (egress node)              oam-server (external server)
#   +-------------------------+            +-------------------------+
#   | eth (oam-net):          |            | 192.168.150.100:8080    |
#   |   192.168.150.x/24     |<--docker--->| HTTP listener           |
#   | EgressIP:               |   oam-net  |                         |
#   |   192.168.150.101/32    |            +-------------------------+
#   +-------------------------+
#
# The EgressIP (192.168.150.101) is assigned to ovn-worker2's oam-net interface.
# Traffic to 192.168.150.0/24 matching the EgressIPTraffic is SNATed to 192.168.150.101.

set -euo pipefail

EGRESS_NODE="ovn-worker2"
OAM_NET="oam-net"
OAM_SUBNET="192.168.150.0/24"
OAM_GW="192.168.150.1"
OAM_SERVER_IP="192.168.150.100"

echo "=== Cleaning up previous state ==="
docker rm -f oam-server 2>/dev/null || true
docker network disconnect "${OAM_NET}" "${EGRESS_NODE}" 2>/dev/null || true
docker network rm "${OAM_NET}" 2>/dev/null || true

echo "=== Creating OAM Docker network ==="
docker network create "${OAM_NET}" --subnet="${OAM_SUBNET}" --gateway="${OAM_GW}"
docker network connect "${OAM_NET}" "${EGRESS_NODE}"

echo "=== Starting external server on OAM network ==="
docker run -d --name oam-server --network "${OAM_NET}" --ip "${OAM_SERVER_IP}" \
    python:3-slim python3 -c "
import http.server, socketserver
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain')
        self.end_headers()
        self.wfile.write(('client=' + self.client_address[0] + '\n').encode())
    def log_message(self, fmt, *args):
        pass
with socketserver.TCPServer(('', 8080), H) as s:
    s.serve_forever()
"

sleep 2
echo "=== Verifying ==="
docker exec oam-server python3 -c "import socket; s=socket.socket(); s.settimeout(1); s.connect(('127.0.0.1',8080)); s.close(); print('OK')" 2>/dev/null || echo "WARNING: oam-server may not be ready yet"

NODE_OAM_IP=$(docker exec "${EGRESS_NODE}" ip -4 addr show | grep "192.168.150" | awk '{print $2}' | cut -d/ -f1 | head -1)
echo "=== Done ==="
echo "OAM network:    ${OAM_SUBNET}"
echo "Egress node IP: ${NODE_OAM_IP}"
echo "External server: ${OAM_SERVER_IP}:8080"
echo "EgressIP:        192.168.150.101"
