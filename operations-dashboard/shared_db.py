"""
Shared Database & Dependency Layer
Simulates the shared state / database used by both the ADO source application
and the GitHub target application during dual-run zero-downtime migration.
"""

import sqlite3
import os
import json
import time

DB_PATH = os.path.join(os.path.dirname(__file__), "shared_state.db")

def init_db():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS orders (
            id TEXT PRIMARY KEY,
            customer_id TEXT,
            amount REAL,
            status TEXT,
            created_at REAL,
            served_by TEXT
        )
    """)
    
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS inventory (
            sku TEXT PRIMARY KEY,
            name TEXT,
            stock INTEGER,
            price REAL
        )
    """)
    
    # Seed initial inventory if empty
    cursor.execute("SELECT COUNT(*) FROM inventory")
    if cursor.fetchone()[0] == 0:
        seed_data = [
            ("SKU-NEO-01", "Cyberpunk Neural Link Interface", 150, 899.99),
            ("SKU-OMARCHY-02", "Omarchy Dual-Boot Micro-Vault", 300, 249.50),
            ("SKU-GITOPS-03", "GitOps Zero-Trust Policy Engine", 500, 1200.00),
            ("SKU-CANARY-04", "Canary Traffic Ingestion Gate", 1000, 49.99)
        ]
        cursor.executemany("INSERT INTO inventory VALUES (?, ?, ?, ?)", seed_data)
    
    conn.commit()
    conn.close()

def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

if __name__ == "__main__":
    init_db()
    print("[+] Shared database initialized at:", DB_PATH)
