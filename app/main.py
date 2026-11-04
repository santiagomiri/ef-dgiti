"""API de la Evaluacion Final DGITI.

Servicio FastAPI que corre en varias instancias EC2 detras de un Application
Load Balancer. Cada respuesta dice que instancia (y en que zona) la atendio,
para que el balanceo de carga se vea en el navegador, en curl y en k6.

Endpoints:
  GET  /             pagina de inicio (instancia, zona, version)
  GET  /health       chequeo de salud del ALB (no depende de la BD)
  GET  /api/info     identidad de la instancia en JSON
  GET  /api/status   estado de la BD primaria y de la replica
  GET  /api/items    lista de items (lee de la replica)
  POST /api/items    crea un item (escribe en la primaria)
  GET  /api/compute  trabajo de CPU para la prueba de carga
  GET  /docs         Swagger UI
"""

import hashlib
import html
import platform
import time
from datetime import UTC, datetime
from typing import Annotated

from fastapi import Depends, FastAPI, HTTPException, Query, Response
from fastapi.responses import HTMLResponse
from pydantic import BaseModel, StringConstraints

from app.config import get_settings
from app.db import Database, DatabaseError
from app.metadata import instance_metadata

settings = get_settings()
STARTED_AT = datetime.now(UTC)

app = FastAPI(
    title="EF DGITI - API de inventario",
    version=settings.app_version,
    description=(
        "Servicio desplegado en AWS con Terraform: ALB + Auto Scaling Group en dos zonas "
        "de disponibilidad + RDS PostgreSQL con replica de lectura."
    ),
)

_database = Database(settings)


def get_db() -> Database:
    return _database


DbDep = Annotated[Database, Depends(get_db)]


class ItemIn(BaseModel):
    name: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=100)]


def served_by() -> dict[str, str]:
    meta = instance_metadata()
    return {"instance_id": meta["instance_id"], "availability_zone": meta["availability_zone"]}


@app.get("/", response_class=HTMLResponse, include_in_schema=False)
def home() -> str:
    meta = instance_metadata()
    rows = {
        "Instancia EC2": meta["instance_id"],
        "Zona de disponibilidad": meta["availability_zone"],
        "IP privada": meta["private_ip"],
        "Version (commit)": settings.app_version,
        "Entorno": settings.app_env,
        "Hora del servidor (UTC)": datetime.now(UTC).strftime("%Y-%m-%d %H:%M:%S"),
    }
    table = "".join(
        f"<tr><th>{html.escape(k)}</th><td>{html.escape(str(v))}</td></tr>" for k, v in rows.items()
    )
    return f"""<!doctype html>
<html lang="es"><head><meta charset="utf-8"><title>EF DGITI</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
 body{{font-family:Segoe UI,Arial,sans-serif;margin:40px auto;max-width:760px;color:#232f3e}}
 h1{{margin-bottom:4px}} p{{color:#555}}
 table{{border-collapse:collapse;width:100%;margin:20px 0}}
 th,td{{border:1px solid #d5dbdb;padding:8px 12px;text-align:left}}
 th{{background:#f2f3f3;width:40%}}
 .ok{{display:inline-block;background:#1d8102;color:#fff;padding:2px 10px;border-radius:12px}}
 a{{color:#0972d3;margin-right:16px}}
</style></head><body>
<h1>Evaluacion Final DGITI - v3</h1>
<p>Servicio en AWS detras de un Application Load Balancer <span class="ok">en linea</span></p>
<table>{table}</table>
<p>Recarga la pagina (F5): el balanceador alterna entre instancias.</p>
<p><a href="/docs">Swagger</a><a href="/health">/health</a><a href="/api/status">/api/status</a>
<a href="/api/items">/api/items</a></p>
</body></html>"""


@app.get("/health", tags=["salud"])
def health() -> dict:
    """Usado por el Target Group del ALB. No consulta la BD a proposito: si RDS
    falla no se deben sacar todas las instancias del balanceador."""
    return {"status": "ok", "version": settings.app_version, **served_by()}


@app.get("/api/info", tags=["salud"])
def info() -> dict:
    meta = instance_metadata()
    return {
        "service": "ef-dgiti-api",
        "version": settings.app_version,
        "environment": settings.app_env,
        "private_ip": meta["private_ip"],
        "python": platform.python_version(),
        "started_at": STARTED_AT.isoformat(),
        "uptime_s": round((datetime.now(UTC) - STARTED_AT).total_seconds(), 1),
        **served_by(),
    }


@app.get("/api/status", tags=["salud"])
def status(response: Response, db: DbDep) -> dict:
    """Chequeo profundo: conecta a la primaria y a la replica."""
    primary = db.check("primary")
    replica = db.check("replica")
    if primary["ok"] and replica["ok"]:
        overall = "ok"
    elif primary["ok"]:
        overall = "degraded"
    else:
        overall = "down"
        response.status_code = 503
    return {
        "status": overall,
        "database": {"primary": primary, "replica": replica},
        "version": settings.app_version,
        **served_by(),
    }


@app.get("/api/items", tags=["items"])
def list_items(db: DbDep, limit: Annotated[int, Query(ge=1, le=100)] = 20) -> dict:
    """Lee de la replica de lectura (si no responde, de la primaria)."""
    try:
        items, source = db.list_items(limit)
    except DatabaseError as exc:
        raise HTTPException(status_code=503, detail=f"Base de datos no disponible: {exc}") from exc
    return {"read_from": source, "count": len(items), "items": items, **served_by()}


@app.post("/api/items", status_code=201, tags=["items"])
def create_item(item: ItemIn, db: DbDep) -> dict:
    """Escribe en la base primaria."""
    who = served_by()
    try:
        row = db.create_item(item.name, who["instance_id"])
    except DatabaseError as exc:
        raise HTTPException(status_code=503, detail=f"Base de datos no disponible: {exc}") from exc
    return {"written_to": "primary", "item": row, **who}


@app.get("/api/compute", tags=["carga"])
def compute(
    n: Annotated[int, Query(ge=1, le=200_000, description="Iteraciones de SHA-256")] = 20_000,
) -> dict:
    """Trabajo de CPU controlado: permite saturar las instancias en la prueba de
    carga y ver el escalado automatico en CloudWatch."""
    start = time.perf_counter()
    digest = b"ef-dgiti"
    for _ in range(n):
        digest = hashlib.sha256(digest).digest()
    return {
        "iterations": n,
        "result": digest.hex()[:16],
        "elapsed_ms": round((time.perf_counter() - start) * 1000, 2),
        **served_by(),
    }
