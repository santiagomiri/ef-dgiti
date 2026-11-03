"""Pruebas de integracion: la API contra un PostgreSQL real.

En GitHub Actions el pipeline levanta un contenedor postgres:16 y define
DB_HOST; localmente se omiten si no hay base configurada.
"""

import os
import uuid

import pytest
from fastapi.testclient import TestClient

from app.config import get_settings
from app.db import Database
from app.main import app

pytestmark = [
    pytest.mark.integration,
    pytest.mark.skipif(not os.getenv("DB_HOST"), reason="DB_HOST no definido"),
]


@pytest.fixture
def client():
    return TestClient(app)


def test_status_conecta_a_la_base_real(client):
    response = client.get("/api/status")
    assert response.status_code == 200
    body = response.json()
    assert body["database"]["primary"]["ok"] is True
    assert body["database"]["replica"]["ok"] is True


def test_item_creado_se_puede_leer(client):
    name = f"item-{uuid.uuid4().hex[:8]}"
    created = client.post("/api/items", json={"name": name})
    assert created.status_code == 201
    item_id = created.json()["item"]["id"]

    listed = client.get("/api/items", params={"limit": 100}).json()
    assert item_id in [item["id"] for item in listed["items"]]


def test_esquema_es_idempotente():
    db = Database(get_settings())
    db.ensure_schema()
    db._schema_ready = False
    db.ensure_schema()  # segunda vez no debe fallar (CREATE TABLE IF NOT EXISTS)
    assert db.check("primary")["ok"] is True
