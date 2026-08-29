"""
Source Application Service (Simulating Azure DevOps Legacy / Source Deployment)
Runs on Port 8001
"""

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import time
import uuid
import shared_db

app = FastAPI(title="Source App (ADO Deployment)", version="1.8.4")

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
        "service": "source-ado-app",
        "origin_build": "Azure DevOps Pipelines Build #1084",
        "version": "1.8.4",
        "uptime_sec": round(time.time() - START_TIME, 2),
        "db_connected": True
    }

@app.get("/api/inventory")
def get_inventory():
    time.sleep(0.015) # Simulate standard ADO VM latency
    conn = shared_db.get_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM inventory")
    rows = [dict(r) for r in cursor.fetchall()]
    conn.close()
    return {
        "source": "Azure DevOps Deployment",
        "version": "1.8.4",
        "items": rows,
        "timestamp": time.time()
    }

@app.post("/api/orders")
def create_order(order: OrderRequest):
    time.sleep(0.020) # Simulate processing time
    order_id = f"ORD-ADO-{uuid.uuid4().hex[:8].upper()}"
    conn = shared_db.get_db()
    cursor = conn.cursor()
    
    cursor.execute(
        "INSERT INTO orders VALUES (?, ?, ?, ?, ?, ?)",
        (order_id, order.customer_id, order.amount, "COMPLETED", time.time(), "Azure DevOps Instance (Port 8801)")
    )
    conn.commit()
    conn.close()
    
    return {
        "order_id": order_id,
        "status": "PROCESSED",
        "processed_by": "Azure DevOps Source Instance",
        "customer_id": order.customer_id,
        "amount": order.amount,
        "timestamp": time.time()
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=8801, log_level="warning")
