"""Pruebas unitarias de la capa de datos y de los metadatos de EC2, con dobles
de prueba en lugar de PostgreSQL y del servicio de metadatos real."""

import io

import psycopg2
import pytest

from app import db as db_module
from app import metadata
from app.config import Settings
from app.db import Database, DatabaseError


def make_settings(**overrides) -> Settings:
    values = dict(
        db_host="primaria.local",
        db_replica_host="replica.local",
        db_port=5432,
        db_name="appdb",
        db_user="app",
        db_password="",
        app_version="test",
        app_env="test",
    )
    values.update(overrides)
    return Settings(**values)


class FakeCursor:
    def __init__(self, conn):
        self.conn = conn
        self.queries: list[str] = []

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False

    def execute(self, sql, params=None):
        if self.conn.fail_queries:
            raise psycopg2.OperationalError("conexion perdida")
        self.queries.append(sql)
        self.conn.executed.append(sql)

    def fetchone(self):
        if self.conn.host == "replica.local":
            return (True, 0.0)
        if "RETURNING" in self.conn.executed[-1]:
            return {"id": 1, "name": "x", "instance_id": "i-1", "created_at": None}
        return (False, 0)

    def fetchall(self):
        return [{"id": 1, "name": "x", "instance_id": "i-1", "created_at": None}]


class FakeConnection:
    def __init__(self, host, fail_queries=False):
        self.host = host
        self.fail_queries = fail_queries
        self.closed = 0
        self.executed: list[str] = []
        self.commits = 0
        self.rollbacks = 0

    def cursor(self, cursor_factory=None):
        return FakeCursor(self)

    def commit(self):
        self.commits += 1

    def rollback(self):
        self.rollbacks += 1


class FakeServer:
    """Reemplaza psycopg2.connect. `broken_hosts` simula una BD caida."""

    def __init__(self) -> None:
        self.broken_hosts: set[str] = set()
        self.failing_queries: set[str] = set()
        self.connections: list[FakeConnection] = []

    def connect(self, **kwargs):
        host = kwargs["host"]
        if host in self.broken_hosts:
            raise psycopg2.OperationalError(f"no se pudo conectar a {host}")
        conn = FakeConnection(host, fail_queries=host in self.failing_queries)
        self.connections.append(conn)
        return conn

    def opened(self, host: str) -> list[FakeConnection]:
        return [conn for conn in self.connections if conn.host == host]


@pytest.fixture(autouse=True)
def fake_pool(monkeypatch):
    server = FakeServer()
    monkeypatch.setattr(db_module.psycopg2, "connect", server.connect)
    return server


def test_sin_host_configurado_lanza_error():
    with pytest.raises(DatabaseError, match="no configurada"):
        Database(make_settings(db_host="")).create_item("x", "i-1")


def test_crear_item_crea_esquema_una_sola_vez(fake_pool):
    database = Database(make_settings())
    database.create_item("a", "i-1")
    database.create_item("b", "i-1")
    schema_runs = [
        sql
        for conn in fake_pool.opened("primaria.local")
        for sql in conn.executed
        if "CREATE TABLE" in sql
    ]
    assert len(schema_runs) == 1


def test_el_pool_reutiliza_la_conexion(fake_pool):
    """Regresion: abrir una conexion por solicitud dispara la latencia en RDS."""
    database = Database(make_settings())
    for _ in range(10):
        database.create_item("x", "i-1")
    assert len(fake_pool.opened("primaria.local")) == 1


def test_listar_lee_de_la_replica():
    items, source = Database(make_settings()).list_items(10)
    assert source == "replica"
    assert items[0]["name"] == "x"


def test_listar_cae_a_la_primaria_si_la_replica_no_responde(fake_pool):
    fake_pool.broken_hosts = {"replica.local"}
    _, source = Database(make_settings()).list_items(10)
    assert source == "primary (respaldo)"


def test_check_de_la_replica_detecta_modo_recuperacion():
    result = Database(make_settings()).check("replica")
    assert result["ok"] is True
    assert result["is_replica"] is True
    assert result["replication_lag_s"] == 0.0


def test_check_reporta_error_si_la_bd_esta_caida(fake_pool):
    fake_pool.broken_hosts = {"primaria.local"}
    result = Database(make_settings()).check("primary")
    assert result["ok"] is False
    assert "no se pudo conectar" in result["error"]


def test_error_de_consulta_hace_rollback(fake_pool):
    fake_pool.failing_queries = {"primaria.local"}
    database = Database(make_settings())
    with pytest.raises(DatabaseError, match="conexion perdida"):
        database.ensure_schema()
    conn = fake_pool.opened("primaria.local")[0]
    assert conn.rollbacks == 1
    assert conn.commits == 0


def test_conexion_cerrada_se_descarta_del_pool(fake_pool):
    pool = Database(make_settings())._pool("primary")
    with pool.connection() as conn:
        conn.closed = 2  # p. ej. RDS se reinicio
    with pool.connection():
        pass
    assert len(fake_pool.opened("primaria.local")) == 2


def test_pool_agotado_lanza_error(monkeypatch):
    monkeypatch.setattr(db_module, "ACQUIRE_TIMEOUT_S", 0.01)
    pool = Database(make_settings())._pool("primary")
    for _ in range(db_module.POOL_SIZE):
        pool._slots.acquire()
    with pytest.raises(DatabaseError, match="agotado"):
        with pool.connection():
            pass


def test_metadatos_de_ec2_con_imdsv2(monkeypatch):
    answers = {
        "/api/token": "token-123",
        "/meta-data/instance-id": "i-0abc",
        "/meta-data/placement/availability-zone": "us-east-1b",
        "/meta-data/local-ipv4": "10.0.12.7",
    }

    def fake_urlopen(request, timeout):
        for suffix, value in answers.items():
            if request.full_url.endswith(suffix):
                return io.BytesIO(value.encode())
        raise AssertionError(request.full_url)

    monkeypatch.delenv("INSTANCE_METADATA_DISABLED", raising=False)
    monkeypatch.setattr(metadata.urllib.request, "urlopen", fake_urlopen)
    metadata.instance_metadata.cache_clear()
    try:
        assert metadata.instance_metadata() == {
            "instance_id": "i-0abc",
            "availability_zone": "us-east-1b",
            "private_ip": "10.0.12.7",
        }
    finally:
        metadata.instance_metadata.cache_clear()


def test_metadatos_fuera_de_aws_usan_respaldo(monkeypatch):
    def no_network(request, timeout):
        raise OSError("sin IMDS")

    monkeypatch.delenv("INSTANCE_METADATA_DISABLED", raising=False)
    monkeypatch.setattr(metadata.urllib.request, "urlopen", no_network)
    metadata.instance_metadata.cache_clear()
    try:
        assert metadata.instance_metadata()["availability_zone"] == "local"
    finally:
        metadata.instance_metadata.cache_clear()
