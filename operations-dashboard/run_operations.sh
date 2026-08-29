#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

echo "================================================================================"
echo "   DUAL-RUN OPERATIONS SUITE ON OMARCHY (ARCH LINUX)"
echo "================================================================================"

# 1. Initialize Shared DB
python3 shared_db.py

# 2. Cleanup old ports
echo "[*] Cleaning up existing ports (8800, 8801, 8802)..."
fuser -k 8800/tcp 8801/tcp 8802/tcp 2>/dev/null || true
sleep 1

# 3. Start Services
echo "[*] Starting Source Application (ADO Deployment on :8801)..."
nohup python3 -m uvicorn service_source_ado:app --host 0.0.0.0 --port 8801 > /tmp/service_source_ado.log 2>&1 &

echo "[*] Starting Target Application (GitHub Deployment on :8802)..."
nohup python3 -m uvicorn service_target_github:app --host 0.0.0.0 --port 8802 > /tmp/service_target_github.log 2>&1 &

echo "[*] Starting Operations Gateway & Parity Dashboard on :8800..."
nohup python3 -m uvicorn operations_gateway:app --host 0.0.0.0 --port 8800 > /tmp/operations_gateway.log 2>&1 &

sleep 2

# 4. Health Checks
echo ""
echo "--- Pre-Flight Health Checks ---"
curl -s -f http://127.0.0.1:8801/health > /dev/null && echo "  [+] Source ADO App (8801) is ONLINE" || echo "  [-] Source App failed"
curl -s -f http://127.0.0.1:8802/health > /dev/null && echo "  [+] Target GitHub App (8802) is ONLINE" || echo "  [-] Target App failed"
curl -s -f http://127.0.0.1:8800/api/gateway/stats > /dev/null && echo "  [+] Operations Gateway (8800) is ONLINE" || echo "  [-] Gateway failed"

# 5. Fire Initial Simulation Burst
echo ""
echo "[*] Firing initial 30 dual-run transactions through the Gateway..."
curl -s -X POST http://127.0.0.1:8800/api/gateway/simulate/30 > /dev/null
sleep 2

# Fetch stats
STATS=$(curl -s http://127.0.0.1:8800/api/gateway/stats)
echo "  [+] Initial Stats: $STATS"

IP=$(ip -4 addr show wlan0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

echo ""
echo "================================================================================"
echo "   OPERATIONS DASHBOARD IS LIVE ON OMARCHY:"
echo "   👉 http://${IP}:8800 (from any device on your Wi-Fi network)"
echo "   👉 http://localhost:8800 (on Omarchy)"
echo "================================================================================"
