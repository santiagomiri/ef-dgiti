"""Configuracion leida de variables de entorno.

En EC2 las variables vienen de /opt/app/app.env (lo escribe user_data.sh).
En GitHub Actions las define el pipeline. Nunca hay credenciales en el codigo.
"""

import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    db_host: str
    db_replica_host: str
    db_port: int
    db_name: str
    db_user: str
    db_password: str
    app_version: str
    app_env: str


def get_settings() -> Settings:
    db_host = os.getenv("DB_HOST", "")
    return Settings(
        db_host=db_host,
        # Sin replica configurada, las lecturas van a la primaria.
        db_replica_host=os.getenv("DB_REPLICA_HOST") or db_host,
        db_port=int(os.getenv("DB_PORT", "5432")),
        db_name=os.getenv("DB_NAME", "appdb"),
        db_user=os.getenv("DB_USER", "app"),
        db_password=os.getenv("DB_PASSWORD", ""),
        app_version=os.getenv("APP_VERSION", "dev"),
        app_env=os.getenv("APP_ENV", "local"),
    )
