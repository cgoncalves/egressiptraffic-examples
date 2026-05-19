#!/bin/bash
# Sets up infrastructure for the advanced multi-EgressIP example.
#
# Three EgressIPs serve one pod:
#   1. eip-default: catch-all on primary network (no infra needed)
#   2. eip-sip: L4-filtered (UDP 5060) on ovn-worker2's OAM interface
#   3. eip-signaling: CIDR-filtered with 2 IPs load-balanced across ovn-worker2 + ovn-worker3
#
# Network layout:
#
#   ovn-worker (pod node, NOT an egress node)
#
#   ovn-worker2 (egress node)                  oam netns (OAM router)
#   +---------------------------+              +----------------------------+
#   | oam-host: 192.168.150.10  |<---veth----->| oam-ns: 192.168.150.1     |
#   | route: 192.168.250.0/24   |              | oam-ext: 192.168.250.1/32  |
#   |   via 192.168.150.1       |              | HTTP :8080, UDP :5060      |
#   +---------------------------+              +----------------------------+
#
#   ovn-worker2 + ovn-worker3 both connected to Docker network "sig-net"
#   sig-ext container on sig-net: 192.168.200.100, HTTP :8081
#   ovn-worker2 sig-net IP: assigned by Docker (192.168.200.x)
#   ovn-worker3 sig-net IP: assigned by Docker (192.168.200.x)
#
# EgressIP assignments:
#   eip-sip:       192.168.150.101 → ovn-worker2 (oam-host)
#   eip-signaling: 192.168.200.101 → ovn-worker2 (sig-net)
#                  192.168.200.201 → ovn-worker3 (sig-net)

set -euo pipefail

EGRESS_NODE1="ovn-worker2"
EGRESS_NODE2="ovn-worker3"
SIG_NET="sig-net"
SIG_SUBNET="192.168.200.0/24"
SIG_GW="192.168.200.1"

# Check that ovn-worker3 exists
if ! docker inspect "${EGRESS_NODE2}" &>/dev/null; then
    echo "ERROR: ${EGRESS_NODE2} does not exist. This example requires 3 worker nodes."
    echo "Recreate the kind cluster with: --num-workers 3"
    exit 1
fi

echo "=== Installing tools on worker nodes ==="
for node in ovn-worker ovn-worker2 ovn-worker3; do
    docker exec "${node}" bash -c "apt-get update -qq && apt-get install -y -qq tcpdump curl python3 socat > /dev/null 2>&1" || true
done

# === OAM network on ovn-worker2 (for eip-sip, L4-filtered) ===
echo "=== Setting up OAM network on ${EGRESS_NODE1} ==="
docker exec "${EGRESS_NODE1}" ip netns del oam 2>/dev/null || true
docker exec "${EGRESS_NODE1}" ip link del oam-host 2>/dev/null || true

docker exec "${EGRESS_NODE1}" ip netns add oam
docker exec "${EGRESS_NODE1}" ip link add oam-host type veth peer name oam-ns
docker exec "${EGRESS_NODE1}" ip link set oam-ns netns oam

docker exec "${EGRESS_NODE1}" ip addr add 192.168.150.10/24 dev oam-host
docker exec "${EGRESS_NODE1}" ip link set oam-host up
docker exec "${EGRESS_NODE1}" ip route add 192.168.250.0/24 via 192.168.150.1 dev oam-host

docker exec "${EGRESS_NODE1}" ip netns exec oam ip addr add 192.168.150.1/24 dev oam-ns
docker exec "${EGRESS_NODE1}" ip netns exec oam ip link set oam-ns up
docker exec "${EGRESS_NODE1}" ip netns exec oam ip link set lo up
docker exec "${EGRESS_NODE1}" ip netns exec oam sysctl -w net.ipv4.ip_forward=1 > /dev/null

docker exec "${EGRESS_NODE1}" ip netns exec oam ip link add oam-ext type dummy
docker exec "${EGRESS_NODE1}" ip netns exec oam ip link set oam-ext up
docker exec "${EGRESS_NODE1}" ip netns exec oam ip addr add 192.168.250.1/32 dev oam-ext
docker exec "${EGRESS_NODE1}" ip netns exec oam ip route add 192.168.250.0/24 dev oam-ext

# HTTP + UDP listeners on OAM
docker exec "${EGRESS_NODE1}" bash -c 'cat > /tmp/http-listener.py << '\''PYEOF'\''
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

docker exec "${EGRESS_NODE1}" bash -c "nsenter --net=/var/run/netns/oam pkill -f 'python3 /tmp/http-listener.py 8080' 2>/dev/null" || true
docker exec -d "${EGRESS_NODE1}" nsenter --net=/var/run/netns/oam python3 /tmp/http-listener.py 8080

docker exec "${EGRESS_NODE1}" bash -c "nsenter --net=/var/run/netns/oam pkill -f 'socat.*UDP-LISTEN:5060' 2>/dev/null" || true
docker exec -d "${EGRESS_NODE1}" nsenter --net=/var/run/netns/oam socat -v UDP-LISTEN:5060,fork SYSTEM:'echo "SIP-OK client=\$SOCAT_PEERADDR"'

# === Signaling network via Docker network (for eip-signaling, load-balanced) ===
echo "=== Setting up signaling Docker network ==="
docker network rm "${SIG_NET}" 2>/dev/null || true
docker network create "${SIG_NET}" --subnet="${SIG_SUBNET}" --gateway="${SIG_GW}" || true

# Connect both egress nodes to the signaling network
docker network connect "${SIG_NET}" "${EGRESS_NODE1}" 2>/dev/null || true
docker network connect "${SIG_NET}" "${EGRESS_NODE2}" 2>/dev/null || true

# Add routes on egress nodes for the signaling destination (192.168.251.0/24 behind the sig-net)
# The external container will have 192.168.251.1 as a dummy IP
SIG_EXT_CONTAINER="sig-ext"
docker rm -f "${SIG_EXT_CONTAINER}" 2>/dev/null || true

# Create external container on sig-net with HTTP listener
docker run -d --name "${SIG_EXT_CONTAINER}" --network "${SIG_NET}" --ip 192.168.200.100 \
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
with socketserver.TCPServer(('', 8081), H) as s:
    s.serve_forever()
"

# Add routes on egress nodes to reach the signaling external container
# The EgressIPTraffic CIDR will be 192.168.200.0/24 (the sig-net subnet itself)
# Since both nodes are connected to sig-net, they can reach 192.168.200.100 directly

sleep 2
echo "=== Verifying listeners ==="
docker exec "${EGRESS_NODE1}" ip netns exec oam ss -tlnp | grep -q ":8080" || echo "WARNING: OAM HTTP listener failed"
docker exec "${EGRESS_NODE1}" ip netns exec oam ss -ulnp | grep -q ":5060" || echo "WARNING: OAM UDP 5060 listener failed"
docker exec "${SIG_EXT_CONTAINER}" ss -tlnp 2>/dev/null | grep -q ":8081" || \
    docker exec "${SIG_EXT_CONTAINER}" python3 -c "import socket; s=socket.socket(); s.bind(('',8081)); print('port 8081 available')" 2>/dev/null || \
    echo "WARNING: sig-ext HTTP 8081 listener may not be ready yet"

# Show IPs assigned on sig-net
W2_SIG_IP=$(docker exec "${EGRESS_NODE1}" ip -4 addr show | grep "192.168.200" | awk '{print $2}' | cut -d/ -f1 | head -1)
W3_SIG_IP=$(docker exec "${EGRESS_NODE2}" ip -4 addr show | grep "192.168.200" | awk '{print $2}' | cut -d/ -f1 | head -1)

echo "=== Done ==="
echo ""
echo "OAM network (ovn-worker2 only):"
echo "  Router:    192.168.150.1"
echo "  Node NIC:  192.168.150.10"
echo "  EgressIP:  192.168.150.101 (L4 filtered, UDP 5060)"
echo "  Listener:  192.168.250.1:8080 (HTTP), 192.168.250.1:5060 (UDP)"
echo ""
echo "Signaling network (Docker network, both egress nodes):"
echo "  ovn-worker2 sig-net IP: ${W2_SIG_IP:-unknown}"
echo "  ovn-worker3 sig-net IP: ${W3_SIG_IP:-unknown}"
echo "  EgressIPs:  192.168.200.101 (ovn-worker2), 192.168.200.201 (ovn-worker3)"
echo "  Listener:   192.168.200.100:8081 (HTTP, sig-ext container)"
echo ""
echo "Catch-all EgressIP: 172.18.0.100 (primary kind network)"
