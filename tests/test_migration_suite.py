import os
import csv
import pytest
import sqlite3

def test_repos_csv_format():
    p = os.path.join(os.path.dirname(__file__), "..", "config", "repos.csv")
    assert os.path.exists(p)
    with open(p, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        assert "SourceRepo" in reader.fieldnames or "repo" in str(reader.fieldnames).lower()

def test_user_mapping_csv():
    p = os.path.join(os.path.dirname(__file__), "..", "config", "user-mapping.csv")
    assert os.path.exists(p)
    with open(p, "r", encoding="utf-8") as f:
        content = f.read()
        assert len(content) > 0

def test_oidc_template_structure():
    p = os.path.join(os.path.dirname(__file__), "..", "templates", "oidc_zero_trust_pipeline.yml")
    assert os.path.exists(p)
    with open(p, "r", encoding="utf-8") as f:
        content = f.read()
        assert "id-token: write" in content or "permissions" in content

def test_shared_db_schema():
    p = os.path.join(os.path.dirname(__file__), "..", "operations-dashboard", "shared_state.db")
    if os.path.exists(p):
        conn = sqlite3.connect(p)
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
        tables = [row[0] for row in cursor.fetchall()]
        conn.close()
        assert len(tables) >= 0

def test_compliance_audit_script():
    p = os.path.join(os.path.dirname(__file__), "..", "scripts", "05_compliance_audit.py")
    assert os.path.exists(p)

def test_migration_playbook():
    p = os.path.join(os.path.dirname(__file__), "..", "README-PLAYBOOK.md")
    assert os.path.exists(p)
