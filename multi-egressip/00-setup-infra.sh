#!/bin/bash
# Sets up two Docker networks with external servers for the multi-EgressIP example.
# Two separate EgressIPs route to different destination networks.
#
# Network layout:
#
#   ovn-worker2 (egress node)              oam-server (192.168.150.100:8080)
#   +-------------------------+            sig-server (192.168.200.100:8081)
#   | EgressIP: 192.168.150.101|<--oam-net-->
#   | EgressIP: 192.168.200.101|<--sig-net-->
#   +-------------------------+

set -euo pipefail

EGRESS_NODE="ovn-worker2"
OAM_NET="oam-net"
SIG_NET="sig-net"

echo "=== Cleaning up previous state ==="
docker rm -f oam-server sig-server 2>/dev/null || true
docker network disconnect "${OAM_NET}" "${EGRESS_NODE}" 2>/dev/null || true
docker network disconnect "${SIG_NET}" "${EGRESS_NODE}" 2>/dev/null || true
docker network rm "${OAM_NET}" 2>/dev/null || true
docker network rm "${SIG_NET}" 2>/dev/null || true

echo "=== Creating Docker networks ==="
docker network create "${OAM_NET}" --subnet=192.168.150.0/24 --gateway=192.168.150.1
docker network create "${SIG_NET}" --subnet=192.168.200.0/24 --gateway=192.168.200.1
docker network connect "${OAM_NET}" "${EGRESS_NODE}"
docker network connect "${SIG_NET}" "${EGRESS_NODE}"

echo "=== Starting external servers ==="
for entry in "oam-server ${OAM_NET} 192.168.150.100 8080" "sig-server ${SIG_NET} 192.168.200.100 8081"; do
    read -r name net ip port <<< "${entry}"
    docker run -d --name "${name}" --network "${net}" --ip "${ip}" \
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
echo "OAM server:  192.168.150.100:8080 (oam-server on oam-net)"
echo "SIG server:  192.168.200.100:8081 (sig-server on sig-net)"
echo "EgressIP #1: 192.168.150.101 (oam-net)"
echo "EgressIP #2: 192.168.200.101 (sig-net)"
