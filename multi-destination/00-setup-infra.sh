#!/bin/bash
# Sets up a Docker network with two external servers for the multi-destination example.
# One EgressIP routes to multiple destination hosts on the same network.
#
# Network layout:
#
#   ovn-worker2 (egress node)              oam-server1 (192.168.150.100:8080)
#   +-------------------------+            oam-server2 (192.168.150.200:8081)
#   | EgressIP: 192.168.150.101|<--oam-net-->
#   +-------------------------+

set -euo pipefail

EGRESS_NODE="ovn-worker2"
OAM_NET="oam-net"

echo "=== Cleaning up previous state ==="
docker rm -f oam-server1 oam-server2 2>/dev/null || true
docker network disconnect "${OAM_NET}" "${EGRESS_NODE}" 2>/dev/null || true
docker network rm "${OAM_NET}" 2>/dev/null || true

echo "=== Creating Docker network ==="
docker network create "${OAM_NET}" --subnet=192.168.150.0/24 --gateway=192.168.150.1
docker network connect "${OAM_NET}" "${EGRESS_NODE}"

echo "=== Starting external servers ==="
for entry in "oam-server1 192.168.150.100 8080" "oam-server2 192.168.150.200 8081"; do
    read -r name ip port <<< "${entry}"
    docker run -d --name "${name}" --network "${OAM_NET}" --ip "${ip}" \
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
with socketserver.TCPServer(('', ${port}), H) as s:
    s.serve_forever()
"
done

sleep 2
echo "=== Done ==="
echo "Server 1: 192.168.150.100:8080 (oam-server1)"
echo "Server 2: 192.168.150.200:8081 (oam-server2)"
echo "EgressIP: 192.168.150.101"
