"""
Target Application Service (Simulating Migrated GitHub Enterprise / Actions Deployment)
Runs on Port 8002
"""

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import time
import uuid
import shared_db

app = FastAPI(title="Target App (GitHub Deployment)", version="2.0.0-gitops")

shared_db.init_db()

class OrderRequest(BaseModel):
    customer_id: str
    amount: float
    sku: str

START_TIME = time.time()

@app.get("/health")
def health():
    return {
        "status": "healthy",
        "service": "target-github-app",
        "origin_build": "GitHub Actions Workflow Run #2001 (Omarchy-GitOps)",
        "version": "2.0.0-gitops",
        "uptime_sec": round(time.time() - START_TIME, 2),
        "db_connected": True
    }

@app.get("/api/inventory")
def get_inventory():
    time.sleep(0.008) # Modernized optimized latency
    conn = shared_db.get_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM inventory")
    rows = [dict(r) for r in cursor.fetchall()]
    conn.close()
    return {
        "source": "GitHub Enterprise Deployment",
        "version": "2.0.0-gitops",
        "items": rows,
        "timestamp": time.time()
    }

@app.post("/api/orders")
def create_order(order: OrderRequest):
    time.sleep(0.010) # Optimized processing time
    order_id = f"ORD-GHO-{uuid.uuid4().hex[:8].upper()}"
    conn = shared_db.get_db()
    cursor = conn.cursor()
    
    cursor.execute(
        "INSERT INTO orders VALUES (?, ?, ?, ?, ?, ?)",
        (order_id, order.customer_id, order.amount, "COMPLETED", time.time(), "GitHub Enterprise Instance (Port 8802)")
    )
    conn.commit()
    conn.close()
    
    return {
        "order_id": order_id,
        "status": "PROCESSED",
        "processed_by": "GitHub Enterprise Target Instance",
        "customer_id": order.customer_id,
        "amount": order.amount,
        "timestamp": time.time()
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=8802, log_level="warning")
