# Matriz de cumplimiento — Evaluación Final DGITI

Cada fila es un requisito textual del enunciado (Prof. Omar Pinzón Ardila), con dónde está implementado y en qué
minuto del video se evidencia. Ruta de archivos relativa a la raíz del repositorio.

## 1. Servicio desplegado

| Requisito | Implementación | Evidencia en video |
|---|---|---|
| Servicio funcional en AWS accesible a través de un endpoint | API FastAPI detrás del ALB: `http://<dns-del-alb>/` (`app/main.py`, `infra/main.tf` §6) | Clip 3 (3:30): navegador en la URL del ALB |
| Al menos un endpoint de validación (`/health`, `/status`, `/api/test` o equivalente) | `/health` (health check del ALB), `/api/status` (primaria y réplica), `/api/info`, Swagger `/docs` | Clip 3: Swagger `/health`, `/api/status` |
| Código fuente versionado en GitHub | <https://github.com/santiagomiri/ef-dgiti> | Clip 4 (4:45): repositorio y Actions |
| Base de datos **con réplica** | RDS PostgreSQL 16 primaria (us-east-1a) + réplica de lectura (us-east-1b) — `infra/main.tf` §4 | Clip 3: `/api/status` (`is_replica` falso/verdadero); POST escribe en primaria, GET lee de réplica |
| Acceso a la BD restringido **únicamente** a la infraestructura privada de la app | Subredes de BD sin ruta a Internet; `publicly_accessible = false`; `sg-db` acepta 5432 **solo** desde `sg-app`, sin reglas de salida | Clip 1 (0:15): Security Groups en el diagrama y en la consola |

## 2. Infraestructura en AWS

| Requisito | Implementación | Evidencia en video |
|---|---|---|
| Disponible ante fallo de una instancia | ASG mínimo 2 instancias en 2 AZ, health check tipo ELB (`/health` cada 10 s) y reemplazo automático | Clip 3: `scripts/prueba-falla.ps1` termina una instancia y el servicio sigue respondiendo 200 |
| Distribución del tráfico entre múltiples instancias | ALB *round robin* sin afinidad de sesión; cada respuesta indica instancia y zona | Clip 3: F5 alterna instancias. Clip 5: `respuestas_por_instancia` y `respuestas_por_zona` en k6 |
| Controles de acceso de red con reglas de seguridad | 3 Security Groups encadenados (`sg-alb` → `sg-app` → `sg-db`), subredes en 3 capas, NAT para salida | Clip 1: diagrama + Resource map de la VPC |

## 3. Infraestructura como Código

| Requisito | Implementación | Evidencia en video |
|---|---|---|
| Terraform obligatorio | 49 recursos con el proveedor `hashicorp/aws` 5.x | Clip 2 (1:30) |
| `provider.tf` | `infra/provider.tf` | Clip 2 |
| `variables.tf` | `infra/variables.tf` (con validaciones y `sensitive`) | Clip 2 |
| `main.tf` | `infra/main.tf` (8 secciones comentadas) | Clip 2 |
| `outputs.tf` | `infra/outputs.tf` | Clip 2 |
| `terraform.tfvars.example` | `infra/terraform.tfvars.example` (el `.tfvars` real está en `.gitignore`) | Clip 2 |
| `user_data.sh` si aplica | `infra/user_data.sh` (instala la API como servicio systemd) | Clip 2 |

## 4. Pipeline CI/CD (`.github/workflows/ci-cd.yml`)

| Requisito | Implementación | Evidencia en video |
|---|---|---|
| GitHub Actions | Workflow `CI-CD` en cada push a `main` | Clip 4 (4:45) |
| Validación del código | `ruff check` + `ruff format --check`; `terraform fmt`, `init`, `validate`; verificación de archivos requeridos | Clip 4: jobs 1 y 2 en verde |
| Ejecución de pruebas | 32 unitarias + 3 de integración contra PostgreSQL 16 real (contenedor de servicio); cobertura ≥ 85 % (real 97,6 %) | Clip 4: pasos de pruebas y tabla del resumen |
| Despliegue o preparación del despliegue | *Instance refresh* del ASG (sin caída) + prueba de humo que verifica el commit en todas las instancias | Clip 4: job 3 y página con la versión nueva |
| Variables o secretos sin exponer credenciales | Secretos `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`; variables `AWS_REGION`, `ASG_NAME`, `ALB_URL`. Contraseña de la BD en SSM Parameter Store (SecureString/KMS), leída por las instancias con su rol IAM: no está en el código ni en el `user_data` | Clip 4: pantalla de Secrets (valores ocultos). Clip 2: `user_data.sh` |

## 5. Prueba de desempeño (`load-tests/carga.js`, `scripts/prueba-carga.ps1`)

| Requisito | Implementación | Evidencia en video |
|---|---|---|
| k6, Apache Benchmark, JMeter o equivalente | k6 con perfiles `humo`, `carga` y `estres` | Clip 5 (6:45) |
| Tiempo de respuesta | `http_req_duration` p50/p90/p95/p99 global y por endpoint | Clip 5: dashboard k6 y resumen |
| Usuarios virtuales o solicitudes concurrentes | Rampa de 0 a 200 VUs (`ramping-vus`) | Clip 5: dashboard k6 |
| Porcentaje de errores | `http_req_failed` con umbral < 5 % | Clip 5: resumen |
| Evidencia de saturación o comportamiento bajo carga | Endpoint `/api/compute` satura CPU → p95 sube → alarma de escalado → ASG de 2 a 4 | Clip 5: CloudWatch (CPU, latencia, instancias) |
| **Ver la operación del balanceador** | `respuestas_por_instancia{instancia:i-...}` y `respuestas_por_zona`; Target Group con instancias nuevas *healthy*; `RequestCountPerTarget` | Clip 5: resumen k6 + consola EC2 Target Groups |
| Relacionar los resultados con la infraestructura | Conclusión: capacidad de 2 × t3.micro, umbral de CPU 50 %, tiempo de reacción del escalado, BD no fue cuello de botella | Clip 5: conclusión |

## 6. Diagrama (`docs/arquitectura.png`, editable `docs/arquitectura.drawio`)

| Debe mostrar | ¿Está? |
|---|---|
| Iconos oficiales de AWS | ✅ librería oficial AWS de draw.io (AWS Architecture Icons) |
| Usuarios | ✅ |
| VPC | ✅ `10.0.0.0/16` |
| Subredes | ✅ 6 (pública, app y BD × 2 AZ) con CIDR |
| Balanceador | ✅ Application Load Balancer |
| Instancias o servicios de cómputo | ✅ EC2 t3.micro en Auto Scaling Group |
| Security Groups | ✅ 3, con sus reglas |
| Base de datos y almacenamiento | ✅ RDS primaria + réplica; EBS gp3 cifrado |
| Flujo de despliegue CI/CD | ✅ verde: push → GitHub Actions → instance refresh → ASG |
| Flujo de tráfico de usuarios | ✅ azul numerado ① → ④ |

## 7. Video (máx. 10 min) y rúbrica

| Rúbrica (peso) | Qué se exige | Clip |
|---|---|---|
| Arquitectura (10 %) | Diagrama, segmentación de red, balanceo, seguridad, alta disponibilidad y decisiones de cómputo | 1 |
| IaC (25 %) | Estructura Terraform + `init`, `plan`, `apply`, `output` | 2 |
| Servicio (10 %) | Servicio funcionando + validación por navegador/Swagger/curl | 3 |
| CI/CD (25 %) | Flujo del pipeline, ejecución exitosa, pruebas unitarias e integración | 4 |
| Desempeño y monitoreo (30 %) | Prueba de carga, balanceador funcionando, métricas en CloudWatch | 5 |
| Requisito general | Demostración en vivo en la **cuenta personal de AWS Academy**; no solo narración ni diapositivas | 1 (evidencia de cuenta) y todos |

## Restricción del entorno documentada

El AWS Academy Learner Lab aplica una política de organización (SCP) que **niega `s3:GetBucketObjectLockConfiguration`**,
operación que el proveedor de Terraform ejecuta al gestionar cualquier bucket S3. Por eso el bucket de logs de acceso
del ALB quedó **parametrizado y apagado** (`enable_alb_access_logs = false`); en una cuenta AWS normal se activa con `true`.
