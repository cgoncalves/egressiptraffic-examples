#!/bin/bash
# Sets up infrastructure for the advanced multi-EgressIP example.
#
# Three EgressIPs serve one pod:
#   1. eip-default: catch-all on primary network (no infra needed)
#   2. eip-sip: L4-filtered (UDP 5060) on ovn-worker2's OAM link network
#   3. eip-signaling: CIDR-filtered with 2 IPs load-balanced across ovn-worker2 + ovn-worker3
#
# Network layout:
#
#   OAM network (oam-router, only ovn-worker2 connects):
#
#   ovn-worker2 (egress node)              oam-router container
#   +---------------------------+         +------------------------------+
#   | oam-link-net:             |         | eth0: 192.168.150.1          |
#   |   192.168.150.x/24        |<-link-->| IP forwarding enabled        |
#   | EgressIP:                 |         |                              |
#   |   192.168.150.101/32      |         | veth-host: 192.168.250.1/24  |
#   +---------------------------+         |   |                          |
#                                         |   v (veth pair)              |
#                                         | netns: oam-server            |
#                                         |   veth-ns: 192.168.250.100  |
#                                         |   HTTP :8080                 |
#                                         +------------------------------+
#
#   Signaling network (sig-router, both ovn-worker2 and ovn-worker3 connect):
#
#   ovn-worker2          ovn-worker3          sig-router container
#   +---------------+   +---------------+   +------------------------------+
#   | sig-link-net: |   | sig-link-net: |   | eth0: 192.168.200.1          |
#   | 192.168.200.x |   | 192.168.200.y |   | IP forwarding enabled        |
#   | EgressIP:     |   | EgressIP:     |   |                              |
#   | .200.101/32   |   | .200.201/32   |   | veth-host: 192.168.251.1/24  |
#   +------+--------+   +------+--------+   |   |                          |
#          |                    |             |   v (veth pair)              |
#          +-------link--------+---link------| netns: sig-server            |
#                                            |   veth-ns: 192.168.251.100  |
#                                            |   HTTP :8081                 |
#                                            +------------------------------+
#
# EgressIP assignments:
#   eip-sip:       192.168.150.101 -> ovn-worker2 (oam-link-net, L4: UDP 5060)
#   eip-signaling: 192.168.200.101 -> ovn-worker2 (sig-link-net)
#                  192.168.200.201 -> ovn-worker3 (sig-link-net)

set -euo pipefail

EGRESS_NODE1="ovn-worker2"
EGRESS_NODE2="ovn-worker3"

# Check that ovn-worker3 exists
if ! docker inspect "${EGRESS_NODE2}" &>/dev/null; then
    echo "ERROR: ${EGRESS_NODE2} does not exist. This example requires 3 worker nodes."
    echo "Recreate the kind cluster with: --num-workers 3"
    exit 1
fi

echo "=== Cleaning up previous state ==="
docker rm -f oam-router sig-router ext-server 2>/dev/null || true
docker network disconnect oam-link-net "${EGRESS_NODE1}" 2>/dev/null || true
docker network disconnect sig-link-net "${EGRESS_NODE1}" 2>/dev/null || true
docker network disconnect sig-link-net "${EGRESS_NODE2}" 2>/dev/null || true
docker network rm oam-link-net sig-link-net 2>/dev/null || true

# === OAM network (for eip-sip, L4-filtered) ===
echo "=== Setting up OAM network ==="
docker network create oam-link-net --subnet=192.168.150.0/24 --gateway=192.168.150.254

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

docker network connect oam-link-net "${EGRESS_NODE1}"
docker exec "${EGRESS_NODE1}" ip route add 192.168.250.0/24 via 192.168.150.1 2>/dev/null || true

# === Signaling network (for eip-signaling, load-balanced across 2 nodes) ===
echo "=== Setting up signaling network ==="
docker network create sig-link-net --subnet=192.168.200.0/24 --gateway=192.168.200.254

docker run -d --name sig-router --network sig-link-net --ip 192.168.200.1 \
    --privileged registry.access.redhat.com/ubi9/ubi \
    bash -c '
        echo 1 > /proc/sys/net/ipv4/ip_forward

        # Create server netns with veth pair
        ip netns add sig-server
        ip link add veth-host type veth peer name veth-ns
        ip link set veth-ns netns sig-server

        ip addr add 192.168.251.1/24 dev veth-host
        ip link set veth-host up

        ip netns exec sig-server ip addr add 192.168.251.100/24 dev veth-ns
        ip netns exec sig-server ip link set veth-ns up
        ip netns exec sig-server ip link set lo up
        ip netns exec sig-server ip route add default via 192.168.251.1

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
        nsenter --net=/var/run/netns/sig-server python3 /tmp/http-listener.py 8081 &

        sleep infinity
    '

docker network connect sig-link-net "${EGRESS_NODE1}"
docker network connect sig-link-net "${EGRESS_NODE2}"
docker exec "${EGRESS_NODE1}" ip route add 192.168.251.0/24 via 192.168.200.1 2>/dev/null || true
docker exec "${EGRESS_NODE2}" ip route add 192.168.251.0/24 via 192.168.200.1 2>/dev/null || true

echo "=== Starting external server on kind network (for catch-all EgressIP verification) ==="
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

sleep 3
echo "=== Verifying ==="
docker exec oam-router curl -s --connect-timeout 2 http://192.168.250.100:8080 || echo "WARNING: oam-router cannot reach server"
docker exec sig-router curl -s --connect-timeout 2 http://192.168.251.100:8081 || echo "WARNING: sig-router cannot reach server"

echo "=== Done ==="
echo ""
echo "OAM network:"
echo "  Link:     192.168.150.0/24 (Docker, ${EGRESS_NODE1} only)"
echo "  Router:   192.168.150.1 (oam-router container)"
echo "  Dest:     192.168.250.0/24 (netns inside oam-router, server: 192.168.250.100:8080)"
echo "  EgressIP: 192.168.150.101 (L4 filtered: UDP 5060)"
echo ""
echo "Signaling network:"
echo "  Link:     192.168.200.0/24 (Docker, both ${EGRESS_NODE1} and ${EGRESS_NODE2})"
echo "  Router:   192.168.200.1 (sig-router container)"
echo "  Dest:     192.168.251.0/24 (netns inside sig-router, server: 192.168.251.100:8081)"
echo "  EgressIPs: 192.168.200.101 (${EGRESS_NODE1}), 192.168.200.201 (${EGRESS_NODE2})"
echo ""
echo "Catch-all EgressIP: 172.18.0.100 (primary kind network)"
echo "External server:  172.18.0.200:9090 (on kind network, for catch-all verification)"
