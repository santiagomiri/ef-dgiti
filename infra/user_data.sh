#!/bin/bash
# =============================================================================
# user_data.sh - Arranque de cada instancia del Auto Scaling Group
# Terraform lo procesa con templatefile() e inyecta los valores entre llaves.
# Se ejecuta una sola vez, como root. Registro en /var/log/user-data.log
# =============================================================================
exec > >(tee -a /var/log/user-data.log) 2>&1
set -euo pipefail
echo "== Inicio user_data: $(date -Is)"

APP_DIR=/opt/app

# 1. Paquetes del sistema (salen a Internet por el NAT Gateway)
dnf install -y git python3.11 python3.11-pip

# 2. Usuario sin privilegios para ejecutar la API
id app >/dev/null 2>&1 || useradd --system --home-dir "$APP_DIR" --shell /sbin/nologin app
mkdir -p "$APP_DIR"

# 3. Codigo fuente desde GitHub (reintentos por si la red tarda)
for intento in 1 2 3 4 5; do
  rm -rf "$APP_DIR/src"
  if git clone --depth 1 --branch "${repo_branch}" "${repo_url}" "$APP_DIR/src"; then
    break
  fi
  echo "git clone fallo (intento $intento), reintentando en 15 s"
  sleep 15
done
test -d "$APP_DIR/src/app"
VERSION=$(git -C "$APP_DIR/src" rev-parse --short=7 HEAD)
echo "Version desplegada: $VERSION"

# 4. Entorno virtual con las dependencias
python3.11 -m venv "$APP_DIR/venv"
"$APP_DIR/venv/bin/pip" install --quiet --upgrade pip
"$APP_DIR/venv/bin/pip" install --quiet -r "$APP_DIR/src/app/requirements.txt"

# 5. Contrasena de la BD: desde SSM Parameter Store (cifrada con KMS) usando el
#    rol IAM de la instancia; asi no viaja en este user_data.
if [ -n "${db_secret_param}" ]; then
  DB_PASSWORD=""
  for intento in 1 2 3 4 5 6; do
    if DB_PASSWORD=$(aws ssm get-parameter --region "${aws_region}" --name "${db_secret_param}" \
        --with-decryption --query Parameter.Value --output text); then
      break
    fi
    echo "Lectura de SSM fallo (intento $intento), reintentando en 10 s"
    sleep 10
  done
  test -n "$DB_PASSWORD"
  echo "Contrasena de la BD obtenida de SSM Parameter Store (${db_secret_param})"
else
  DB_PASSWORD='${db_password}'
fi

# 6. Configuracion (solo legible por el usuario app)
cat > "$APP_DIR/app.env" <<EOF
DB_HOST=${db_host}
DB_REPLICA_HOST=${db_replica_host}
DB_NAME=${db_name}
DB_USER=${db_user}
DB_PASSWORD=$DB_PASSWORD
APP_VERSION=$VERSION
APP_ENV=${app_env}
EOF
chown -R app:app "$APP_DIR"
chmod 600 "$APP_DIR/app.env"

# 7. Servicio systemd: arranca con el sistema y se reinicia si falla
cat > /etc/systemd/system/ef-api.service <<EOF
[Unit]
Description=EF DGITI API (FastAPI + uvicorn)
After=network-online.target
Wants=network-online.target

[Service]
User=app
Group=app
EnvironmentFile=$APP_DIR/app.env
WorkingDirectory=$APP_DIR/src
ExecStart=$APP_DIR/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port ${app_port} --workers 2 --no-access-log
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now ef-api.service

# 8. Verificacion local
for intento in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:${app_port}/health"; then
    echo
    echo "== API en linea: $(date -Is)"
    break
  fi
  sleep 2
done
echo "== Fin user_data: $(date -Is)"
