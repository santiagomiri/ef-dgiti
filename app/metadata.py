"""Identidad de la instancia EC2 que atiende la solicitud.

Se consulta una sola vez el servicio de metadatos (IMDSv2, con token) y se
guarda en cache. Fuera de AWS (local o CI) devuelve valores de respaldo.
"""

import os
import socket
import urllib.request
from functools import lru_cache

IMDS_URL = "http://169.254.169.254/latest"
TIMEOUT_S = 1


def _imds_get(path: str, token: str) -> str:
    request = urllib.request.Request(
        f"{IMDS_URL}/meta-data/{path}", headers={"X-aws-ec2-metadata-token": token}
    )
    with urllib.request.urlopen(request, timeout=TIMEOUT_S) as response:
        return response.read().decode()


@lru_cache(maxsize=1)
def instance_metadata() -> dict[str, str]:
    fallback = {
        "instance_id": socket.gethostname(),
        "availability_zone": "local",
        "private_ip": "127.0.0.1",
    }
    if os.getenv("INSTANCE_METADATA_DISABLED") == "1":
        return fallback
    try:
        token_request = urllib.request.Request(
            f"{IMDS_URL}/api/token",
            method="PUT",
            headers={"X-aws-ec2-metadata-token-ttl-seconds": "21600"},
        )
        with urllib.request.urlopen(token_request, timeout=TIMEOUT_S) as response:
            token = response.read().decode()
        return {
            "instance_id": _imds_get("instance-id", token),
            "availability_zone": _imds_get("placement/availability-zone", token),
            "private_ip": _imds_get("local-ipv4", token),
        }
    except OSError:
        return fallback
