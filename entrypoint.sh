#!/usr/bin/env bash
set -euo pipefail

DATA_DIR="${DATA_DIR:-/data}"
WG_IFACE="${WG_IFACE:-wg0}"

CONTROLLER_URL="${CONTROLLER_URL:-}"     # http://controller_public_ip:9000
JOIN_TOKEN="${JOIN_TOKEN:-}"
NODE_ID="${NODE_ID:-}"

if [ -z "$CONTROLLER_URL" ] || [ -z "$JOIN_TOKEN" ] || [ -z "$NODE_ID" ]; then
  echo "Missing env: CONTROLLER_URL, JOIN_TOKEN, NODE_ID"
  exit 1
fi

mkdir -p "$DATA_DIR" /etc/wireguard

KEY_PRIV="$DATA_DIR/node.key"
KEY_PUB="$DATA_DIR/node.pub"

if [ ! -f "$KEY_PRIV" ]; then
  umask 077
  wg genkey | tee "$KEY_PRIV" | wg pubkey > "$KEY_PUB"
fi

NODE_PUBKEY="$(cat "$KEY_PUB")"

echo "[*] Joining controller..."
JOIN_JSON="$(python3 - <<PY
import json, os, requests
url=os.environ["CONTROLLER_URL"].rstrip("/") + "/join"
hdr={"X-Join-Token": os.environ["JOIN_TOKEN"]}
payload={"node_id": os.environ["NODE_ID"], "node_pubkey": os.environ["NODE_PUBKEY"]}
r=requests.post(url, json=payload, headers=hdr, timeout=30)
print(r.text)
r.raise_for_status()
PY
)"
echo "$JOIN_JSON" > "$DATA_DIR/join.json"

NODE_IP="$(python3 -c 'import json; print(json.load(open("/data/join.json"))["node_ip"])')"
CTRL_PUB="$(python3 -c 'import json; print(json.load(open("/data/join.json"))["controller_pubkey"])')"
ENDPOINT="$(python3 -c 'import json; print(json.load(open("/data/join.json"))["endpoint"])')"
ALLOWED="$(python3 -c 'import json; print(json.load(open("/data/join.json"))["allowed_ips"])')"

if [ -z "$ENDPOINT" ] || [ "$ENDPOINT" = "None" ]; then
  echo "Controller did not provide WG_ENDPOINT. Set WG_ENDPOINT on controller (PUBLIC_IP:51820)."
  exit 1
fi

PRIVKEY="$(cat "$KEY_PRIV")"

cat > /etc/wireguard/${WG_IFACE}.conf <<EOF
[Interface]
Address = ${NODE_IP}/32
PrivateKey = ${PRIVKEY}

[Peer]
PublicKey = ${CTRL_PUB}
Endpoint = ${ENDPOINT}
AllowedIPs = ${ALLOWED}
PersistentKeepalive = 25
EOF

echo "[*] Bringing up WireGuard..."
wg-quick down "${WG_IFACE}" >/dev/null 2>&1 || true
wg-quick up "${WG_IFACE}"

# стартуем node-api только на WG IP
NODE_API_PORT="${NODE_API_PORT:-8000}"
echo "[*] Starting node VM API on ${NODE_IP}:${NODE_API_PORT}"
exec gunicorn -b "${NODE_IP}:${NODE_API_PORT}" app:app
