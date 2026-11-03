"""Pruebas unitarias: la API con una base de datos falsa (sin red ni RDS)."""

from datetime import UTC, datetime

import pytest
from fastapi.testclient import TestClient

from app.config import get_settings
from app.db import DatabaseError
from app.main import app, get_db
from app.metadata import instance_metadata


class FakeDatabase:
    def __init__(self) -> None:
        self.items: list[dict] = []
        self.primary_ok = True
        self.replica_ok = True

    def create_item(self, name: str, instance_id: str) -> dict:
        if not self.primary_ok:
            raise DatabaseError("primaria caida")
        item = {
            "id": len(self.items) + 1,
            "name": name,
            "instance_id": instance_id,
            "created_at": datetime.now(UTC),
        }
        self.items.append(item)
        return item

    def list_items(self, limit: int) -> tuple[list[dict], str]:
        if not (self.primary_ok or self.replica_ok):
            raise DatabaseError("sin base de datos")
        source = "replica" if self.replica_ok else "primary (respaldo)"
        return list(reversed(self.items))[:limit], source

    def check(self, role: str) -> dict:
        ok = self.primary_ok if role == "primary" else self.replica_ok
        return {"role": role, "ok": ok, "is_replica": role == "replica"}


@pytest.fixture
def fake_db():
    return FakeDatabase()


@pytest.fixture
def client(fake_db):
    app.dependency_overrides[get_db] = lambda: fake_db
    yield TestClient(app)
    app.dependency_overrides.clear()


def test_health_responde_ok(client):
    response = client.get("/health")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert body["instance_id"]
    assert body["availability_zone"] == "local"


def test_inicio_muestra_instancia_y_zona(client):
    response = client.get("/")
    assert response.status_code == 200
    assert "text/html" in response.headers["content-type"]
    assert instance_metadata()["instance_id"] in response.text
    assert "Zona de disponibilidad" in response.text


def test_info_incluye_version_e_instancia(client):
    body = client.get("/api/info").json()
    assert body["service"] == "ef-dgiti-api"
    assert body["version"] == get_settings().app_version
    assert {"instance_id", "availability_zone", "uptime_s"} <= body.keys()


def test_compute_es_determinista(client):
    first = client.get("/api/compute", params={"n": 1000}).json()
    second = client.get("/api/compute", params={"n": 1000}).json()
    assert first["iterations"] == 1000
    assert first["result"] == second["result"]
    assert first["elapsed_ms"] >= 0


@pytest.mark.parametrize("n", [0, -5, 200_001])
def test_compute_rechaza_valores_fuera_de_rango(client, n):
    assert client.get("/api/compute", params={"n": n}).status_code == 422


def test_crear_y_listar_items(client):
    created = client.post("/api/items", json={"name": "  Servidor web  "})
    assert created.status_code == 201
    body = created.json()
    assert body["written_to"] == "primary"
    assert body["item"]["name"] == "Servidor web"

    listed = client.get("/api/items").json()
    assert listed["read_from"] == "replica"
    assert listed["count"] == 1
    assert listed["items"][0]["name"] == "Servidor web"


@pytest.mark.parametrize("payload", [{"name": ""}, {"name": "   "}, {"name": "x" * 101}, {}])
def test_crear_item_valida_nombre(client, payload):
    assert client.post("/api/items", json=payload).status_code == 422


def test_crear_item_con_bd_caida_devuelve_503(client, fake_db):
    fake_db.primary_ok = False
    response = client.post("/api/items", json={"name": "x"})
    assert response.status_code == 503
    assert "Base de datos no disponible" in response.json()["detail"]


def test_listar_cae_a_la_primaria_si_la_replica_falla(client, fake_db):
    fake_db.replica_ok = False
    assert client.get("/api/items").json()["read_from"] == "primary (respaldo)"


def test_listar_sin_bd_devuelve_503(client, fake_db):
    fake_db.primary_ok = fake_db.replica_ok = False
    assert client.get("/api/items").status_code == 503


@pytest.mark.parametrize(
    ("primary_ok", "replica_ok", "expected", "code"),
    [
        (True, True, "ok", 200),
        (True, False, "degraded", 200),
        (False, True, "down", 503),
    ],
)
def test_status_refleja_estado_de_la_bd(client, fake_db, primary_ok, replica_ok, expected, code):
    fake_db.primary_ok, fake_db.replica_ok = primary_ok, replica_ok
    response = client.get("/api/status")
    assert response.status_code == code
    assert response.json()["status"] == expected


def test_swagger_y_openapi_disponibles(client):
    assert client.get("/docs").status_code == 200
    paths = client.get("/openapi.json").json()["paths"]
    assert {"/health", "/api/status", "/api/items", "/api/compute"} <= paths.keys()


def test_config_usa_la_primaria_si_no_hay_replica(monkeypatch):
    monkeypatch.setenv("DB_HOST", "primaria.local")
    monkeypatch.delenv("DB_REPLICA_HOST", raising=False)
    assert get_settings().db_replica_host == "primaria.local"
