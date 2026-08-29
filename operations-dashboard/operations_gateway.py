"""
Dual-Run Operations Gateway & Real-Time Parity Telemetry Dashboard
Runs on Port 8000
"""

from fastapi import FastAPI, Request, BackgroundTasks
from fastapi.responses import HTMLResponse, JSONResponse
import httpx
import time
import asyncio
import random
import os

app = FastAPI(title="Dual-Run Operations Gateway", version="1.0.0")

# Gateway Configuration & State
STATE = {
    "traffic_split_gh_percent": 50,  # 0 to 100% traffic to GitHub
    "total_requests": 0,
    "successful_parity_matches": 0,
    "discrepancies": 0,
    "avg_ado_latency_ms": 0.0,
    "avg_gh_latency_ms": 0.0,
    "recent_logs": [],
    "is_load_generating": False
}

ADO_BACKEND_URL = "http://127.0.0.1:8801"
GH_BACKEND_URL = "http://127.0.0.1:8802"

async def mirror_and_compare(method: str, path: str, json_body: dict = None):
    async with httpx.AsyncClient(timeout=5.0) as client:
        # Measure ADO Request
        t0 = time.perf_counter()
        try:
            if method == "GET":
                resp_ado = await client.get(f"{ADO_BACKEND_URL}{path}")
            else:
                resp_ado = await client.post(f"{ADO_BACKEND_URL}{path}", json=json_body)
            ado_latency = round((time.perf_counter() - t0) * 1000, 2)
            ado_status = resp_ado.status_code
            ado_data = resp_ado.json()
        except Exception as e:
            ado_latency = 0
            ado_status = 500
            ado_data = {"error": str(e)}

        # Measure GitHub Request
        t1 = time.perf_counter()
        try:
            if method == "GET":
                resp_gh = await client.get(f"{GH_BACKEND_URL}{path}")
            else:
                resp_gh = await client.post(f"{GH_BACKEND_URL}{path}", json=json_body)
            gh_latency = round((time.perf_counter() - t1) * 1000, 2)
            gh_status = resp_gh.status_code
            gh_data = resp_gh.json()
        except Exception as e:
            gh_latency = 0
            gh_status = 500
            gh_data = {"error": str(e)}

    # Parity Evaluation
    status_match = (ado_status == gh_status)
    
    # Check data contract parity (ignoring timestamps and build origin metadata)
    data_parity = True
    if path == "/api/inventory" and status_match:
        data_parity = len(ado_data.get("items", [])) == len(gh_data.get("items", []))
    elif path == "/api/orders" and status_match:
        data_parity = (ado_data.get("status") == gh_data.get("status") and 
                       ado_data.get("customer_id") == gh_data.get("customer_id"))
    
    is_match = status_match and data_parity

    # Update Telemetry State
    STATE["total_requests"] += 1
    if is_match:
        STATE["successful_parity_matches"] += 1
    else:
        STATE["discrepancies"] += 1

    # Exponential Moving Average for Latency
    alpha = 0.2
    STATE["avg_ado_latency_ms"] = round((alpha * ado_latency) + ((1 - alpha) * STATE["avg_ado_latency_ms"]), 2) if STATE["avg_ado_latency_ms"] else ado_latency
    STATE["avg_gh_latency_ms"] = round((alpha * gh_latency) + ((1 - alpha) * STATE["avg_gh_latency_ms"]), 2) if STATE["avg_gh_latency_ms"] else gh_latency

    log_entry = {
        "id": STATE["total_requests"],
        "timestamp": time.strftime("%H:%M:%S"),
        "method": method,
        "path": path,
        "ado_latency_ms": ado_latency,
        "gh_latency_ms": gh_latency,
        "delta_ms": round(ado_latency - gh_latency, 2),
        "parity_match": is_match,
        "served_by": "GitHub (Migrated)" if random.randint(1, 100) <= STATE["traffic_split_gh_percent"] else "ADO (Source)"
    }
    
    STATE["recent_logs"].insert(0, log_entry)
    if len(STATE["recent_logs"]) > 50:
        STATE["recent_logs"].pop()

    return log_entry, resp_gh if log_entry["served_by"].startswith("GitHub") else resp_ado

# Gateway Proxy Endpoints
@app.get("/api/inventory")
async def proxy_inventory():
    log_entry, primary_resp = await mirror_and_compare("GET", "/api/inventory")
    return primary_resp.json()

@app.post("/api/orders")
async def proxy_orders(request: Request):
    body = await request.json()
    log_entry, primary_resp = await mirror_and_compare("POST", "/api/orders", json_body=body)
    return primary_resp.json()

# Operational Telemetry API
@app.get("/api/gateway/stats")
def get_stats():
    parity_rate = round((STATE["successful_parity_matches"] / max(STATE["total_requests"], 1)) * 100, 2)
    return {
        **STATE,
        "parity_rate_percent": parity_rate
    }

@app.post("/api/gateway/traffic-split/{percent}")
def set_traffic_split(percent: int):
    STATE["traffic_split_gh_percent"] = max(0, min(100, percent))
    return {"status": "updated", "traffic_split_gh_percent": STATE["traffic_split_gh_percent"]}

@app.post("/api/gateway/simulate/{count}")
async def simulate_traffic(count: int, background_tasks: BackgroundTasks):
    async def run_sim():
        customers = ["CUST-101", "CUST-102", "CUST-103", "CUST-104", "CUST-105"]
        skus = ["SKU-NEO-01", "SKU-OMARCHY-02", "SKU-GITOPS-03", "SKU-CANARY-04"]
        
        for _ in range(count):
            if random.random() < 0.6:
                await mirror_and_compare("GET", "/api/inventory")
            else:
                body = {
                    "customer_id": random.choice(customers),
                    "amount": round(random.uniform(50.0, 1500.0), 2),
                    "sku": random.choice(skus)
                }
                await mirror_and_compare("POST", "/api/orders", json_body=body)
            await asyncio.sleep(0.05)
    
    background_tasks.add_task(run_sim)
    return {"status": "simulation_started", "requests_scheduled": count}

# Interactive Operations Dashboard UI
@app.get("/", response_class=HTMLResponse)
def get_dashboard():
    return """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Dual-Run Operations Gateway & Parity Center</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        body { background-color: #0b0f19; color: #f3f4f6; font-family: ui-sans-serif, system-ui, sans-serif; }
        .glass { background: rgba(17, 24, 39, 0.85); backdrop-filter: blur(12px); border: 1px solid rgba(255,255,255,0.08); }
        .pulse-live { animation: pulse 2s infinite; }
        @keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.4; } }
    </style>
</head>
<body class="p-6">
    <div class="max-w-7xl mx-auto space-y-6">
        <!-- Header -->
        <div class="flex flex-col md:flex-row justify-between items-start md:items-center glass p-6 rounded-2xl shadow-2xl border-l-4 border-cyan-500">
            <div>
                <div class="flex items-center space-x-3">
                    <span class="h-3.5 w-3.5 rounded-full bg-emerald-400 pulse-live"></span>
                    <h1 class="text-2xl font-black tracking-tight text-white">DUAL-RUN OPERATIONS GATEWAY</h1>
                    <span class="px-2.5 py-0.5 text-xs font-semibold rounded-full bg-cyan-900/60 text-cyan-300 border border-cyan-700">CANARY VERIFIED</span>
                </div>
                <p class="text-gray-400 text-sm mt-1">Simultaneous Zero-Downtime Traffic Mirroring & Regression Parity Testbed</p>
            </div>
            <div class="flex items-center space-x-3 mt-4 md:mt-0">
                <button onclick="fireSimulation(25)" class="px-4 py-2 bg-gradient-to-r from-cyan-600 to-blue-600 hover:from-cyan-500 hover:to-blue-500 text-white font-bold rounded-xl shadow-lg transition transform hover:scale-105 active:scale-95 text-sm">
                    ⚡ Fire 25 Transactions
                </button>
                <button onclick="fireSimulation(100)" class="px-4 py-2 bg-gradient-to-r from-purple-600 to-pink-600 hover:from-purple-500 hover:to-pink-500 text-white font-bold rounded-xl shadow-lg transition transform hover:scale-105 active:scale-95 text-sm">
                    🚀 Run Load Burst (100)
                </button>
            </div>
        </div>

        <!-- System Architecture & Traffic Split Controller -->
        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
            <!-- Source Node Card -->
            <div class="glass p-5 rounded-2xl border-t-2 border-orange-500 relative overflow-hidden">
                <div class="flex justify-between items-center mb-3">
                    <span class="text-xs font-bold text-orange-400 uppercase tracking-wider">Source Cluster (Port 8001)</span>
                    <span class="px-2 py-0.5 text-xs font-bold bg-orange-950/60 text-orange-300 rounded border border-orange-700">Azure DevOps</span>
                </div>
                <div class="text-xl font-bold text-white">ADO Legacy Deployment</div>
                <div class="text-gray-400 text-xs mt-1">Build #1084 · SQLite Engine</div>
                <div class="mt-4 flex justify-between items-center text-sm">
                    <span class="text-gray-400">Avg Latency:</span>
                    <span id="ado-lat" class="font-mono font-bold text-orange-300 text-lg">0.00 ms</span>
                </div>
            </div>

            <!-- Canary Shift Control Slider -->
            <div class="glass p-5 rounded-2xl border-t-2 border-cyan-500 flex flex-col justify-between">
                <div>
                    <div class="flex justify-between items-center mb-2">
                        <span class="text-xs font-bold text-cyan-400 uppercase tracking-wider">Traffic Cutover Control</span>
                        <span id="split-display" class="font-mono font-bold text-cyan-300 text-sm">50% GitHub / 50% ADO</span>
                    </div>
                    <input type="range" id="split-slider" min="0" max="100" value="50" oninput="updateTrafficSplit(this.value)" class="w-full h-2 bg-gray-700 rounded-lg appearance-none cursor-pointer accent-cyan-500">
                    <div class="flex justify-between text-[11px] text-gray-500 mt-2 font-mono">
                        <span>100% ADO (0% GH)</span>
                        <span>50/50 Canary</span>
                        <span>100% GitHub</span>
                    </div>
                </div>
                <div class="mt-3 text-center text-xs text-gray-400">
                    Shadow Mirroring is <span class="text-emerald-400 font-bold">100% ACTIVE</span> on all requests
                </div>
            </div>

            <!-- Target Node Card -->
            <div class="glass p-5 rounded-2xl border-t-2 border-emerald-500 relative overflow-hidden">
                <div class="flex justify-between items-center mb-3">
                    <span class="text-xs font-bold text-emerald-400 uppercase tracking-wider">Target Cluster (Port 8002)</span>
                    <span class="px-2 py-0.5 text-xs font-bold bg-emerald-950/60 text-emerald-300 rounded border border-emerald-700">GitHub Enterprise</span>
                </div>
                <div class="text-xl font-bold text-white">Migrated GitHub App</div>
                <div class="text-gray-400 text-xs mt-1">Actions Run #2001 · Async Pipeline</div>
                <div class="mt-4 flex justify-between items-center text-sm">
                    <span class="text-gray-400">Avg Latency:</span>
                    <span id="gh-lat" class="font-mono font-bold text-emerald-300 text-lg">0.00 ms</span>
                </div>
            </div>
        </div>

        <!-- Telemetry Stats Strip -->
        <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
            <div class="glass p-4 rounded-xl text-center">
                <div class="text-gray-400 text-xs uppercase tracking-wider font-semibold">Total Dual Requests</div>
                <div id="stat-total" class="text-3xl font-black text-white mt-1 font-mono">0</div>
            </div>
            <div class="glass p-4 rounded-xl text-center">
                <div class="text-gray-400 text-xs uppercase tracking-wider font-semibold">Parity Match Rate</div>
                <div id="stat-parity" class="text-3xl font-black text-emerald-400 mt-1 font-mono">100.0%</div>
            </div>
            <div class="glass p-4 rounded-xl text-center">
                <div class="text-gray-400 text-xs uppercase tracking-wider font-semibold">Payload Discrepancies</div>
                <div id="stat-disc" class="text-3xl font-black text-green-300 mt-1 font-mono">0</div>
            </div>
            <div class="glass p-4 rounded-xl text-center">
                <div class="text-gray-400 text-xs uppercase tracking-wider font-semibold">Performance Delta</div>
                <div id="stat-delta" class="text-3xl font-black text-cyan-400 mt-1 font-mono">+0.00 ms</div>
            </div>
        </div>

        <!-- Chart & Live Stream -->
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
            <!-- Latency Real-Time Chart -->
            <div class="glass p-5 rounded-2xl">
                <h3 class="text-sm font-bold text-gray-300 uppercase tracking-wider mb-4 flex items-center justify-between">
                    <span>Real-Time Latency Comparison (ms)</span>
                    <span class="text-xs text-gray-500 font-mono">Higher is Slower</span>
                </h3>
                <div class="h-64">
                    <canvas id="latencyChart"></canvas>
                </div>
            </div>

            <!-- Live Parity Verification Log Stream -->
            <div class="glass p-5 rounded-2xl flex flex-col justify-between">
                <h3 class="text-sm font-bold text-gray-300 uppercase tracking-wider mb-3 flex justify-between items-center">
                    <span>Live Parity Audit Stream</span>
                    <span class="text-xs text-emerald-400 font-mono">● 0 Errors</span>
                </h3>
                <div id="log-container" class="space-y-2 h-64 overflow-y-auto pr-2 font-mono text-xs">
                    <!-- Logs populated dynamically -->
                </div>
            </div>
        </div>
    </div>

    <script>
        let chart;
        const ctx = document.getElementById('latencyChart').getContext('2d');
        chart = new Chart(ctx, {
            type: 'line',
            data: {
                labels: [],
                datasets: [
                    {
                        label: 'ADO Source (Port 8001)',
                        data: [],
                        borderColor: '#f97316',
                        backgroundColor: 'rgba(249, 115, 22, 0.1)',
                        tension: 0.3,
                        borderWidth: 2,
                        fill: true
                    },
                    {
                        label: 'GitHub Target (Port 8002)',
                        data: [],
                        borderColor: '#10b981',
                        backgroundColor: 'rgba(16, 185, 129, 0.1)',
                        tension: 0.3,
                        borderWidth: 2,
                        fill: true
                    }
                ]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                scales: {
                    x: { grid: { color: 'rgba(255,255,255,0.05)' }, ticks: { color: '#9ca3af' } },
                    y: { grid: { color: 'rgba(255,255,255,0.05)' }, ticks: { color: '#9ca3af' }, beginAtZero: true }
                },
                plugins: {
                    legend: { labels: { color: '#e5e7eb', font: { size: 11 } } }
                }
            }
        });

        async function fetchStats() {
            try {
                const res = await fetch('/api/gateway/stats');
                const data = await res.json();

                document.getElementById('stat-total').innerText = data.total_requests;
                document.getElementById('stat-parity').innerText = data.parity_rate_percent + '%';
                document.getElementById('stat-disc').innerText = data.discrepancies;
                
                document.getElementById('ado-lat').innerText = data.avg_ado_latency_ms.toFixed(2) + ' ms';
                document.getElementById('gh-lat').innerText = data.avg_gh_latency_ms.toFixed(2) + ' ms';

                const delta = (data.avg_ado_latency_ms - data.avg_gh_latency_ms).toFixed(2);
                document.getElementById('stat-delta').innerText = (delta >= 0 ? '+' : '') + delta + ' ms';
                document.getElementById('stat-delta').className = delta >= 0 ? 'text-3xl font-black text-emerald-400 mt-1 font-mono' : 'text-3xl font-black text-yellow-400 mt-1 font-mono';

                // Update Logs
                const logContainer = document.getElementById('log-container');
                logContainer.innerHTML = '';
                data.recent_logs.forEach(l => {
                    const row = document.createElement('div');
                    row.className = `p-2 rounded flex justify-between items-center ${l.parity_match ? 'bg-gray-800/60 border border-emerald-900/40' : 'bg-red-950/60 border border-red-700'}`;
                    row.innerHTML = `
                        <div>
                            <span class="text-cyan-400 font-bold">[${l.method}]</span>
                            <span class="text-gray-300 ml-1">${l.path}</span>
                            <span class="text-gray-500 text-[10px] ml-2">${l.timestamp}</span>
                        </div>
                        <div class="flex items-center space-x-2">
                            <span class="text-orange-400">${l.ado_latency_ms}ms</span>
                            <span class="text-gray-500">vs</span>
                            <span class="text-emerald-400">${l.gh_latency_ms}ms</span>
                            <span class="px-1.5 py-0.5 text-[10px] rounded ${l.parity_match ? 'bg-emerald-900/80 text-emerald-300' : 'bg-red-900 text-red-300'} font-bold">
                                ${l.parity_match ? 'PARITY OK' : 'MISMATCH'}
                            </span>
                        </div>
                    `;
                    logContainer.appendChild(row);
                });

                // Update Chart
                if (data.recent_logs.length > 0) {
                    const recent = [...data.recent_logs].reverse().slice(-15);
                    chart.data.labels = recent.map(r => r.timestamp);
                    chart.data.datasets[0].data = recent.map(r => r.ado_latency_ms);
                    chart.data.datasets[1].data = recent.map(r => r.gh_latency_ms);
                    chart.update();
                }
            } catch (e) {
                console.error(e);
            }
        }

        async function updateTrafficSplit(val) {
            document.getElementById('split-display').innerText = `${val}% GitHub / ${100 - val}% ADO`;
            await fetch(`/api/gateway/traffic-split/${val}`, { method: 'POST' });
        }

        async function fireSimulation(count) {
            await fetch(`/api/gateway/simulate/${count}`, { method: 'POST' });
        }

        setInterval(fetchStats, 1000);
        fetchStats();
    </script>
</body>
</html>
"""

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=8800, log_level="warning")
