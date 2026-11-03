"""Acceso a RDS PostgreSQL: escrituras en la primaria, lecturas en la replica.

Cada proceso mantiene un pool pequeno por rol ("primary" / "replica") para no
agotar las conexiones de una db.t3.micro cuando el Auto Scaling agrega
instancias durante la prueba de carga.
"""

import threading
import time
from contextlib import contextmanager

import psycopg2
from psycopg2 import pool as pg_pool
from psycopg2.extras import RealDictCursor

from app.config import Settings

POOL_SIZE = 5
ACQUIRE_TIMEOUT_S = 5
CONNECT_TIMEOUT_S = 3
SCHEMA_LOCK_ID = 4242

SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS items (
    id          SERIAL PRIMARY KEY,
    name        VARCHAR(100) NOT NULL,
    instance_id VARCHAR(64)  NOT NULL,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
)
"""

# En la replica: retraso = 0 si ya aplico todo lo recibido; si no, segundos
# desde la ultima transaccion replicada.
CHECK_SQL = """
SELECT pg_is_in_recovery(),
       CASE
         WHEN NOT pg_is_in_recovery() THEN 0
         WHEN pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn() THEN 0
         ELSE COALESCE(EXTRACT(EPOCH FROM now() - pg_last_xact_replay_timestamp()), 0)
       END
"""


class DatabaseError(Exception):
    """Fallo de conexion, de consulta o pool agotado."""


def _safe_rollback(conn) -> None:
    if not conn.closed:
        try:
            conn.rollback()
        except psycopg2.Error:
            pass


class _Pool:
    def __init__(self, **conn_kwargs) -> None:
        # minconn=0: no se conecta hasta la primera solicitud.
        self._pool = pg_pool.ThreadedConnectionPool(0, POOL_SIZE, **conn_kwargs)
        self._slots = threading.BoundedSemaphore(POOL_SIZE)

    @contextmanager
    def connection(self):
        if not self._slots.acquire(timeout=ACQUIRE_TIMEOUT_S):
            raise DatabaseError("pool de conexiones agotado")
        try:
            try:
                conn = self._pool.getconn()
            except psycopg2.Error as exc:
                raise DatabaseError(str(exc).strip()) from exc
            try:
                yield conn
                conn.commit()
            except psycopg2.Error as exc:
                _safe_rollback(conn)
                raise DatabaseError(str(exc).strip()) from exc
            except Exception:
                _safe_rollback(conn)
                raise
            finally:
                # Una conexion rota (p. ej. reinicio de RDS) se descarta.
                self._pool.putconn(conn, close=bool(conn.closed))
        finally:
            self._slots.release()


class Database:
    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._pools: dict[str, _Pool] = {}
        self._lock = threading.Lock()
        self._schema_ready = False

    def _host(self, role: str) -> str:
        if role == "primary":
            return self._settings.db_host
        return self._settings.db_replica_host

    def _pool(self, role: str) -> _Pool:
        with self._lock:
            if role not in self._pools:
                host = self._host(role)
                if not host:
                    raise DatabaseError("base de datos no configurada (DB_HOST vacio)")
                self._pools[role] = _Pool(
                    host=host,
                    port=self._settings.db_port,
                    dbname=self._settings.db_name,
                    user=self._settings.db_user,
                    password=self._settings.db_password,
                    connect_timeout=CONNECT_TIMEOUT_S,
                    application_name="ef-dgiti-api",
                )
            return self._pools[role]

    def ensure_schema(self) -> None:
        if self._schema_ready:
            return
        with self._pool("primary").connection() as conn, conn.cursor() as cur:
            # El candado evita que varias instancias creen la tabla a la vez.
            cur.execute("SELECT pg_advisory_xact_lock(%s)", (SCHEMA_LOCK_ID,))
            cur.execute(SCHEMA_SQL)
        self._schema_ready = True

    def create_item(self, name: str, instance_id: str) -> dict:
        self.ensure_schema()
        with (
            self._pool("primary").connection() as conn,
            conn.cursor(cursor_factory=RealDictCursor) as cur,
        ):
            cur.execute(
                "INSERT INTO items (name, instance_id) VALUES (%s, %s) "
                "RETURNING id, name, instance_id, created_at",
                (name, instance_id),
            )
            return dict(cur.fetchone())

    def _select_items(self, role: str, limit: int) -> list[dict]:
        with (
            self._pool(role).connection() as conn,
            conn.cursor(cursor_factory=RealDictCursor) as cur,
        ):
            cur.execute(
                "SELECT id, name, instance_id, created_at FROM items ORDER BY id DESC LIMIT %s",
                (limit,),
            )
            return [dict(row) for row in cur.fetchall()]

    def list_items(self, limit: int) -> tuple[list[dict], str]:
        """Lee de la replica; si no responde, cae a la primaria."""
        self.ensure_schema()
        try:
            return self._select_items("replica", limit), "replica"
        except DatabaseError:
            return self._select_items("primary", limit), "primary (respaldo)"

    def check(self, role: str) -> dict:
        start = time.perf_counter()
        result = {"role": role, "host": self._host(role)}
        try:
            with self._pool(role).connection() as conn, conn.cursor() as cur:
                cur.execute(CHECK_SQL)
                in_recovery, lag = cur.fetchone()
            result.update(
                ok=True, is_replica=bool(in_recovery), replication_lag_s=round(float(lag), 3)
            )
        except DatabaseError as exc:
            result.update(ok=False, error=str(exc)[:200])
        result["latency_ms"] = round((time.perf_counter() - start) * 1000, 2)
        return result
