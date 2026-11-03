# Evaluación Final DGITI — Guía paso a paso (de cero a video entregado)

> **Entrega:** mañana 10:00. **Meta:** 5,0. Esta guía cubre **todo**: preparar PCs, subir el repo, desplegar
> en la cuenta de **cada** integrante, configurar el pipeline, prueba de carga, diagrama, grabar, entregar y destruir.
>
> Todo se pega en **PowerShell** (clic derecho = pegar). 📸 = toma captura (Win + Shift + S) por si algo falla al grabar.
> Cualquier texto en **rojo** que no esté en la sección de problemas: para y pide ayuda.

---

## 0. Qué ya está hecho (y cómo cumple cada requisito)

El proyecto `ef-dgiti/` ya está completo y **verificado localmente**: 32 pruebas unitarias + 3 de integración contra PostgreSQL 16 real pasan (97,6 % de cobertura),
`ruff` sin errores, `terraform validate` → *Success*, la API y k6 funcionan.

| Requisito del enunciado | Dónde se cumple |
|---|---|
| Servicio accesible por endpoint | ALB → `http://<dns>/` |
| Endpoint de validación | `/health`, `/api/status`, `/api/info`, Swagger `/docs` |
| Código en GitHub | Repo público (Fase A) |
| BD con réplica, acceso solo desde la red privada de la app | RDS primaria + réplica, subredes de BD sin Internet, `sg-db` solo acepta `sg-app` |
| Disponible ante fallo de una instancia | ASG mín. 2 en 2 AZ + health check ELB + `scripts/prueba-falla.ps1` |
| Distribución del tráfico | ALB round robin; cada respuesta dice qué instancia/zona atendió |
| Controles de red | 3 Security Groups encadenados + subredes por capas |
| Terraform con los 6 archivos | `infra/provider.tf, variables.tf, main.tf, outputs.tf, terraform.tfvars.example, user_data.sh` |
| CI/CD: validación, pruebas, despliegue, secretos | `.github/workflows/ci-cd.yml` (3 jobs) + GitHub Secrets |
| Prueba de desempeño (tiempo, VUs, % error, saturación, balanceador) | `load-tests/carga.js` perfil `estres` + dashboard k6 + CloudWatch |
| Diagrama con iconos oficiales AWS | `docs/arquitectura.drawio` |
| Monitoreo | Dashboard CloudWatch `ef-dgiti` + 4 alarmas |

---

## 1. Organización: trabajo individual

Eres el **único integrante**: presentas los **5 bloques** (= los 5 criterios de la rúbrica) en **tu** cuenta de
AWS Academy Learner Lab. Así se cumple de sobra la regla de que "cada integrante demuestre en su propia cuenta".

| Bloque | Criterio (peso) | Duración en video |
|---|---|---|
| **A** | Arquitectura (10 %) | 1:15 (+ 15 s de intro) |
| **B** | Infraestructura como Código (25 %) | 2:00 |
| **C** | Servicio desplegado (10 %) | 1:15 |
| **D** | Pipeline CI/CD (25 %) | 2:00 |
| **E** | Desempeño y monitoreo (30 %) | 2:40 |

Graba **un clip por bloque** y únelos en Clipchamp (ver `GUION_VIDEO.md`): puedes repetir un bloque si te
equivocas y cortar las esperas. Las fases de esta guía que dicen "todos" o "persona X" las haces tú.

---

## 2. Cronograma sugerido (hoy → mañana 10:00)

| Hora | Qué | Estado |
|---|---|---|
| Hecho | Herramientas, repo en GitHub, pipeline (pruebas + Terraform en verde), diagrama | ✅ |
| Ahora | Fase B: `terraform apply` (~25 min) | 🔄 |
| +30 min | Fase C: secretos y variables de GitHub + run de despliegue en verde | ⏳ |
| +45 min | Fase D: k6 de humo y de estrés, CloudWatch, prueba de falla; anotar los números | ⏳ |
| +1 h 30 | **Ensayo** de cada bloque con el guion (cronometrado) | ⏳ |
| +2 h | **Grabación** por clips (con sesión del Learner Lab recién iniciada) | ⏳ |
| +3 h | Edición en Clipchamp y revisión con la lista final (sección 10) | ⏳ |
| Antes de las 8:00 | **Entregar** (no esperes al último minuto) | ⏳ |
| Después de entregar | `terraform destroy` | ⏳ |

> ⚠️ Las credenciales del Learner Lab **cambian en cada sesión**. Si cierras el Learner Lab o se acaba el tiempo,
> repite el **Paso B2** (credenciales) y la **Fase C2** (secretos de GitHub).

---

## 3. Preparar el PC (✅ ya hecho en tu PC)

### 3.1 Instalar herramientas (si ya las tienes, sáltalo)
Abre **PowerShell** y pega una línea a la vez:
```powershell
winget install --id Git.Git -e
winget install --id Hashicorp.Terraform -e
winget install --id Amazon.AWSCLI -e
winget install k6 --source winget
```
Cierra PowerShell y abre uno **nuevo**. Verifica (📸 `00-herramientas.png`):
```powershell
git --version; terraform version; aws --version; k6 version
```

### 3.2 Permitir scripts de PowerShell (solo para tu usuario)
```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```
Responde `S` (Sí).

### 3.3 Cuenta de GitHub
Cada uno necesita usuario de GitHub (para clonar no hace falta iniciar sesión porque el repo es público).

---

## Fase A — Subir el código a GitHub (✅ ya hecho)

**A1.** En <https://github.com/new>: nombre `ef-dgiti`, **Public**, **sin** README ni .gitignore → **Create repository**.

**A2.** En PowerShell, entra a la carpeta del proyecto (ajusta la ruta a donde quedó `ef-dgiti`):
```powershell
cd "$HOME\Documents\EF-DGITI\ef-dgiti"
```

**A3.** Configura tu identidad de Git (una sola vez) y sube el código. Cambia `TU_USUARIO`:
```powershell
git config --global user.name "Tu Nombre"
git config --global user.email "tu-correo@ejemplo.com"
git init -b main
git add .
git commit -m "Evaluacion final: app, Terraform, CI/CD, k6 y diagrama"
git remote add origin https://github.com/TU_USUARIO/ef-dgiti.git
git push -u origin main
```
Si pide iniciar sesión, se abre el navegador: autoriza. 📸 `A-repo.png` (el repo en GitHub con las carpetas).

> El primer push dispara el pipeline. Los jobs 1 y 2 deben quedar en ✅ verde. El job 3 (despliegue)
> fallará con *"Faltan las variables ASG_NAME..."*: **es normal**, todavía no hay infraestructura. Se arregla en la Fase C.

**A4.** Comparte con el grupo la URL: `https://github.com/TU_USUARIO/ef-dgiti`.
Si alguien más del grupo hará commits, agrégalo en **Settings → Collaborators**.

---

## Fase B — Desplegar la infraestructura en tu cuenta (~35 min)

### B1. Iniciar el Learner Lab
Canvas → tarjeta verde **AWS Academy Learner Lab** (la del parcial, NO la morada de Cloud Foundations) → **Modules** → **Launch AWS Academy Learner Lab** → **Start Lab** → espera el círculo 🟢 junto a "AWS".
> La sesión dura 4 h: al acabarse, AWS **detiene** las instancias (no las borra) y se reactivan con el siguiente **Start Lab**. El crédito del curso es limitado: no dejen la infraestructura viva más de lo necesario.

### B2. Credenciales en tu PC
En PowerShell, desde la carpeta donde vas a trabajar:
```powershell
cd "$HOME\Documents"
git clone https://github.com/santiagomiri/ef-dgiti.git
cd ef-dgiti
powershell -ExecutionPolicy Bypass -File .\scripts\credenciales.ps1
```
La ventana queda esperando. **No la toques.** En el Learner Lab: **AWS Details** → **AWS CLI: Show** → selecciona todo
el bloque que empieza con `[default]` → clic derecho → **Copiar**. PowerShell dice **Credenciales guardadas** y
muestra tu ARN (`...assumed-role/voclabs/user...`). 📸 `B2-credenciales.png`

> El dueño del repo ya tiene la carpeta: solo hace `cd` a ella y corre el script.

### B3. Crear tu `terraform.tfvars`
```powershell
cd infra
copy terraform.tfvars.example terraform.tfvars
notepad terraform.tfvars
```
Cambia **solo** estas dos líneas, guarda y cierra:
- `app_repo_url = "https://github.com/santiagomiri/ef-dgiti.git"` (el repo del grupo)
- `db_password = "..."` → inventa una de **12 a 40 letras y números, sin símbolos** (ej. `GrupoDgiti2026Final`).

> `terraform.tfvars` está en `.gitignore`: **nunca** se sube a GitHub. Eso es lo que se explica en el video como
> "manejo de credenciales sin exponerlas".

### B3.5 Verificación previa (1 min)
Desde la raíz del repo (`cd ..` si estás en `infra`):
```powershell
.\scripts\verificar-todo.ps1
```
Las secciones 1 a 5 deben salir en **[OK]** verde (la 6 sale en *AVISO* hasta que despliegues). Si algo sale en
**[FALLA]**, el mensaje dice exactamente qué corregir. Luego vuelve a `cd infra`.

### B4. Ciclo Terraform (guarda evidencia de TODO)
```powershell
terraform init
```
📸 `B4-init.png` → *Terraform has been successfully initialized!*

```powershell
terraform plan
```
📸 `B4-plan.png` → al final: **Plan: 45 to add, 0 to change, 0 to destroy** (45 con la configuración por defecto para el Learner Lab).

```powershell
terraform apply
```
Escribe `yes`. **Tarda 20–25 minutos** (la réplica de RDS es lo más lento). No cierres la ventana.
> 💡 **Graba esta pantalla con Win + Alt + R** (Xbox Game Bar) o OBS desde que escribes `yes` hasta el final:
> la persona del bloque B la usará acelerada en el video. Al final: **Apply complete! Resources: 45 added** 📸 `B4-apply.png`

```powershell
terraform output
```
📸 `B4-output.png` (URL del ALB, endpoints, nombre del ASG, endpoints de RDS, URL del dashboard).

### B5. Comprobar que funciona (espera 3–4 min después del apply: las instancias instalan la app)
```powershell
$url = terraform output -raw alb_url
start $url
curl.exe -s "$url/health"
curl.exe -s "$url/api/status"
```
- La página muestra **Instancia EC2 / Zona / Versión**. **F5 varias veces: cambia de instancia y de zona.** 📸 `B5-web.png`
- `/api/status` debe decir `"status":"ok"`, la primaria con `"is_replica":false` y la réplica con `"is_replica":true`. 📸

> Si sale **502/503 Bad Gateway**: las instancias aún se están instalando. Espera 2 min y vuelve a probar.
> Si a los 10 min sigue igual → sección 11, problema 4.

### B6. Recorrido por la consola (cada uno practica lo que mostrará)
Consola AWS (en el Learner Lab, clic en **AWS** 🟢) → región **N. Virginia**:
- **VPC → Your VPCs → `ef-dgiti-vpc` → pestaña Resource map** (excelente para el bloque A). 📸
- **VPC → Security groups** → `ef-dgiti-sg-alb`, `-sg-app`, `-sg-db` → **Inbound rules**. 📸
- **EC2 → Load Balancers → `ef-dgiti-alb`** y **Target groups → `ef-dgiti-tg` → Targets** (2 *healthy* en 2 zonas). 📸
- **EC2 → Auto Scaling Groups → `ef-dgiti-asg`** (Min 2 / Max 4) → pestaña **Automatic scaling** (política CPU 50 %). 📸
- **RDS → Databases** → `ef-dgiti-db-primaria` (*Primary*) y `ef-dgiti-db-replica` (*Replica*). 📸
- **CloudWatch → Dashboards → `ef-dgiti`**. 📸

Opcional, todo por CLI (sirve de respaldo): `cd ..` y luego `.\scripts\ver-recursos.ps1`.

---

## Fase C — Pipeline CI/CD (~20 min)

### C1. Variables del repositorio (datos no sensibles)
En la carpeta `infra` de **tu** despliegue:
```powershell
terraform output github_actions_variables
```
GitHub → repo → **Settings → Secrets and variables → Actions → pestaña Variables → New repository variable**.
Crea las 3, copiando los valores **sin comillas**:

| Nombre | Valor |
|---|---|
| `AWS_REGION` | `us-east-1` |
| `ASG_NAME` | `ef-dgiti-asg` |
| `ALB_URL` | `http://ef-dgiti-alb-XXXX.us-east-1.elb.amazonaws.com` (sin `/` al final) |

### C2. Secretos (credenciales del Learner Lab) — **repetir cada vez que inicies una sesión nueva del Learner Lab**
Pestaña **Secrets → New repository secret**. Para no mostrar las claves en pantalla, desde la raíz del repo:
```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\copiar-secretos.ps1
```
El script copia al portapapeles un valor a la vez: creas el secreto, pegas con Ctrl+V, guardas y presionas Enter.

| Secreto | Origen |
|---|---|
| `AWS_ACCESS_KEY_ID` | `aws_access_key_id` |
| `AWS_SECRET_ACCESS_KEY` | `aws_secret_access_key` |
| `AWS_SESSION_TOKEN` | `aws_session_token` |

📸 `C2-secretos.png` (se ven los nombres, **nunca** los valores).

### C3. Probar el pipeline completo con un cambio visible
Edita el título de la página para que el despliegue se note en el navegador:
```powershell
notepad app\main.py
```
Busca `<h1>Evaluacion Final DGITI</h1>` y cámbialo por `<h1>Evaluacion Final DGITI - v2</h1>`. Guarda.
```powershell
git add app/main.py
git commit -m "Version 2 de la pagina de inicio"
git push
```
GitHub → pestaña **Actions** → el run nuevo. Debe quedar **todo en verde** (📸 de cada job):
1. **Validación de código y pruebas** (~1 min): abre los pasos *Pruebas unitarias* (32 passed, cobertura) y
   *Pruebas de integración* (3 passed contra PostgreSQL). Abajo, el **resumen** con la tabla de pruebas.
2. **Validación de infraestructura** (~30 s): fmt, init, validate.
3. **Despliegue en AWS** (8–12 min): el *rolling update* reemplaza las instancias de a una (sin caída), y la
   *prueba de humo* verifica que **todas** responden el commit nuevo. Resumen con la tabla instancia/zona/versión.

Abre la URL del ALB: ahora dice **"- v2"** y la **Versión (commit)** coincide con el commit en GitHub. 📸

> Para el video, el bloque D necesitará otro run: repite C3 con `v3` **~12 minutos antes** de su turno
> (así el run termina mientras los demás presentan), o muestra este run ya terminado + uno nuevo arrancando.

---

## Fase D — Prueba de carga, balanceador y CloudWatch (~30 min)

Desde la **raíz** del repo, con tu despliegue:

### D1. Ver el balanceador repartiendo
```powershell
.\scripts\verificar-balanceo.ps1 -Solicitudes 20
```
Tabla final: ~50 % por instancia, cada una en una zona distinta. 📸

### D2. Prueba de humo (30 s)
```powershell
$url = terraform -chdir=infra output -raw alb_url
k6 run -e BASE_URL=$url -e PERFIL=humo load-tests/carga.js
```
Todo ✓ en verde.

### D3. Prueba de estrés (la del video, ~8 min)
```powershell
.\scripts\prueba-carga.ps1
```
El script toma la URL del ALB y las instancias en servicio, abre el dashboard de k6 y guarda el resumen
(`resumen-k6-estres-*.txt`) y el reporte HTML (`reporte-k6-estres-*.html`) en `load-tests\resultados\`.
En el resumen, `respuestas_por_instancia` muestra cuántas solicitudes atendió **cada instancia**: es la
evidencia directa de la operación del balanceador. (Prueba de humo de 30 s: `.\scripts\prueba-carga.ps1 -Perfil humo`.)

Mientras corre:
1. Abre **<http://127.0.0.1:5665>**: dashboard en vivo de k6 (usuarios virtuales, solicitudes/s, latencias).
2. Abre el **dashboard de CloudWatch** (`terraform -chdir=infra output -raw cloudwatch_dashboard_url`),
   rango **1h**, auto-refresh **10 s**. A los 3–5 min verás: solicitudes ↑, latencia p95 ↑, **CPU > 50 %** (línea
   del objetivo), y luego **Auto Scaling: Deseadas 2 → 3 → 4**.
3. **EC2 → Target groups → ef-dgiti-tg → Targets**: aparecen instancias nuevas *initial* → *healthy*. 📸
4. **EC2 → Auto Scaling Groups → ef-dgiti-asg → Activity**: *"Launching a new EC2 instance... alarm TargetTracking..."* 📸

Al terminar, k6 imprime el resumen (📸 completo) y deja el reporte HTML en `load-tests/resultados/` (ábrelo, se ve muy bien en video).

**Llena esta tabla con TUS números (la dirás en el video):**

| Métrica | Valor |
|---|---|
| Usuarios virtuales máximos | 200 |
| Solicitudes totales / por segundo | ___ / ___ |
| Latencia p50 / p95 / p99 | ___ / ___ / ___ |
| % de errores (`http_req_failed`) | ___ % |
| Respuestas por zona (us-east-1a / us-east-1b) | ___ / ___ |
| CPU máxima del ASG en CloudWatch | ___ % |
| Instancias: inicio → máximo | 2 → ___ |
| Minuto en que escaló | ___ |

> **Si la CPU no pasa de 50 %** (no escala): repite con más trabajo por solicitud: añade `-e ITERACIONES=40000`.
> **Si hay muchos errores (>5 %)** es *evidencia de saturación*, no un fracaso: explícalo (ver guion).
> Después de la prueba el ASG vuelve solo a 2 instancias en ~15 min (scale-in).

### D4. Prueba de alta disponibilidad (bloque C)
```powershell
.\scripts\prueba-falla.ps1
```
Termina una instancia y consulta el servicio cada segundo: siguen saliendo **200** (atiende la otra instancia) y
al final se ve la actividad del ASG lanzando el reemplazo. 📸

---

## Fase E — Diagrama (✅ ya hecho)

**Ya está hecho:** `docs/arquitectura.png` (3409×2163, exportado con draw.io) y el editable `docs/arquitectura.drawio`.
La persona A solo debe **estudiarlo** para explicarlo (guion, bloque A). Si quieren modificarlo:

1. Ábrelo con **draw.io Desktop** (ya instalado en el PC de Santiago) o en <https://app.diagrams.net>
   → **Abrir desde → Dispositivo** → `docs/arquitectura.drawio`.
2. Los iconos son de la librería oficial **AWS** de draw.io (*Más formas → AWS*), basada en los
   *AWS Architecture Icons*. Si el profe exige expresamente el paquete 2026: en
   <https://aws.amazon.com/architecture/icons/> descarga el *Asset Package* y reemplaza los iconos que cambien.
3. **Archivo → Exportar como → PNG** desde la app **web** (app.diagrams.net), zoom 200 %, borde 20, fondo blanco →
   reemplaza `docs/arquitectura.png` y **revisa que se vean CloudWatch, EBS y Auto Scaling a la derecha**
   (la exportación por línea de comandos de draw.io Desktop recorta la imagen),
   y súbelo con `git add docs ; git commit -m "Diagrama actualizado" ; git push` (vuelve a desplegar; es correcto).

**Lo que muestra el diagrama** (todo lo que exige el enunciado): usuarios, VPC, 6 subredes en 2 AZ, ALB,
instancias en Auto Scaling Group, 3 Security Groups, RDS primaria + réplica, almacenamiento EBS/RDS cifrado, CloudWatch,
**flujo de tráfico** (azul ①→④) y **flujo de CI/CD** (verde: push → Actions → reemplazo gradual de instancias → ASG).

---

## Fase F — Grabación

### F1. Formato recomendado
**Una reunión de Google Meet / Teams / Zoom grabada**, con cámara encendida, donde cada integrante
**comparte su propia pantalla** en su turno. Es la evidencia más fuerte de "en vivo" y de participación de cada uno.
Alternativa: cada uno graba su bloque con OBS/Xbox Game Bar y se unen en **Clipchamp** (viene con Windows).

### F2. Antes de grabar (cada integrante)
- [ ] Learner Lab **iniciado** y con tiempo de sobra (si quedan < 60 min, **Start Lab** de nuevo y repite B2).
- [ ] `.\scripts\verificar-todo.ps1` termina en **TODO LISTO** (incluye health, réplica, 2 zonas sanas y `plan` sin cambios).
- [ ] `terraform plan` dice **No changes** (todo sigue desplegado). Si algo cambió, `terraform apply`.
- [ ] El navegador con las pestañas del guion **ya abiertas** y con sesión iniciada en la consola.
- [ ] PowerShell con **letra grande** (Ctrl + rueda del mouse) y fondo oscuro; navegador al 125 %.
- [ ] Notificaciones silenciadas (Windows: *No molestar*). Cierra WhatsApp/Correo.
- [ ] **Nunca** mostrar `terraform.tfvars`, `~/.aws/credentials` ni AWS Details con las claves visibles.
- [ ] Persona D: lanzó el push `v3` ~12 min antes de su turno. Persona E: lanzó k6 `estres` ~6 min antes.

### F3. Al inicio de **cada** bloque (evidencia de la cuenta propia — obligatorio)
1. Di tu nombre completo.
2. Muestra **Canvas → AWS Academy Learner Lab (tarjeta verde) → Launch AWS Academy Learner Lab** con tu nombre visible y el círculo 🟢.
3. Abre la consola y señala la esquina superior derecha (`voclabs/user...`).
4. En PowerShell: `aws sts get-caller-identity` (muestra tu cuenta).

### F4. Durante
Sigue `GUION_VIDEO.md`. Habla mirando la pantalla, **mueve el mouse sobre lo que nombras**, no leas.
Cronometra: el total debe quedar en **9:30–9:50**. **Nunca más de 10:00.**

### F5. Edición
Corta silencios y esperas (por ejemplo, el `terraform apply` acelerado x16 con un texto "acelerado 16x").
Exporta en 1080p. Revisa el audio de cada persona.

---

## Fase G — Entrega y destrucción

1. Sube el video (YouTube **no listado** o Drive con acceso "cualquiera con el enlace") y **pruébalo en una
   ventana de incógnito**.
2. En la tarea: enlace del video + enlace del repo de GitHub (+ el PNG del diagrama si permite adjuntos).
3. **Después** de entregar, cada integrante en su carpeta `infra` (con credenciales vigentes):
```powershell
terraform destroy
```
Escribe `yes` (~15 min) → **Destroy complete!** 📸 Luego **End Lab** en el Learner Lab.

> Si te sobra tiempo, no destruyas hasta que salga la nota: el profe podría pedir revisar algo.
> Pero el NAT Gateway, el ALB y RDS consumen crédito del Learner Lab (~USD 2–3 por día por cuenta).

---

## 10. Lista final antes de entregar (marquen todo)

- [ ] Duración ≤ 10:00.
- [ ] **Cada integrante** aparece, dice su nombre, muestra **su** AWS Academy y hace algo técnico en vivo.
- [ ] Bloque A: diagrama explicado (red, seguridad, HA, cómputo) + Resource map de la VPC.
- [ ] Bloque B: se ven los 6 archivos Terraform y se ejecutan **init, plan, apply y output**.
- [ ] Bloque C: navegador + Swagger/curl/Postman + `/health` + `/api/status` (réplica) + balanceo + prueba de falla.
- [ ] Bloque D: flujo del pipeline, run en verde, **pruebas unitarias e integración** visibles, secretos ocultos, despliegue verificado.
- [ ] Bloque E: k6 corriendo (VUs, latencia, % errores), **ALB repartiendo**, CloudWatch con CPU/latencia/escalado, conclusión con números.
- [ ] Ninguna credencial visible en ningún momento.
- [ ] Enlace del video probado en incógnito.

---

## 11. Problemas comunes y soluciones

| # | Síntoma | Solución |
|---|---|---|
| 1 | `InvalidClientTokenId` / `ExpiredToken` | Credenciales vencidas: Paso B2 de nuevo (y C2 para GitHub). |
| 2 | `terraform plan`: error con el NAT Gateway / Elastic IP no permitido | En `terraform.tfvars`: `enable_nat_gateway = false` (las EC2 van a subredes públicas pero el SG sigue aceptando solo al ALB). `terraform apply`. |
| 3 | `AccessDenied ... s3:GetBucketObjectLockConfiguration ... service control policy` | Restricción del Learner Lab: deja `enable_alb_access_logs = false` (valor por defecto). Si quedó un bucket a medias: `terraform state rm "aws_s3_bucket.alb_logs[0]"` y `aws s3 rb s3://<bucket> --force`. |
| 4 | El ALB da 502/503 más de 10 min | EC2 → Instances → una `ef-dgiti-app` → **Actions → Monitor and troubleshoot → Get system log**: busca `== API en linea`. Si dice `git clone fallo`: el repo no es público o `app_repo_url` está mal → corrígelo en `terraform.tfvars` y `terraform apply` (reemplaza las instancias). |
| 5 | `/api/status` con `"degraded"` | La réplica aún se está creando o reiniciando. Espera 5 min. |
| 6 | Apply: `DBInstanceAlreadyExists` o `already exists` | Quedó algo de un intento anterior: `terraform apply` otra vez; si sigue, bórralo en la consola o cambia `project_name`. |
| 7 | Apply se corta a la mitad (se venció la sesión) | Credenciales nuevas (B2) y `terraform apply` otra vez: continúa desde donde quedó. |
| 8 | Job 3 del pipeline: `Faltan las variables` | Fase C1. |
| 9 | Job 3: `The security token included in the request is invalid` | Secretos vencidos: Fase C2 y en Actions → **Re-run jobs**. |
| 10 | Job 3: `El reemplazo de i-... no quedo sano en 10 minutos` | Revisa el log de arranque de la instancia nueva (problema 4). Si fue algo transitorio, en Actions → **Re-run jobs**. |
| 11 | Job 1 falla en `ruff format --check` | Alguien editó el código a mano: corre `ruff format .` (o deshaz el cambio) y sube. |
| 12 | k6: `thresholds ... have been crossed` (exit 99) | Normal en `estres` si se saturó: es la evidencia de saturación. Explica qué umbral se cruzó y por qué. |
| 13 | `No se puede cargar el archivo ... la ejecución de scripts está deshabilitada` | Paso 3.2, o usa `powershell -ExecutionPolicy Bypass -File .\scripts\...` |
| 14 | `terraform destroy` se queda en el bucket o la réplica | Espera; si falla, `terraform destroy` otra vez. |

---

## 12. Preguntas probables (respuestas cortas para sustentar)

**¿Por qué tres capas de subredes?** Defensa en profundidad: solo el ALB y el NAT tienen exposición pública; las
instancias no tienen IP pública; la BD ni siquiera tiene ruta a Internet.

**¿Por qué Security Groups que referencian otros SG y no IPs?** Porque las IP de las instancias cambian con el
Auto Scaling; la regla "5432 solo desde sg-app" sigue valiendo para cualquier instancia nueva.

**¿Qué pasa si se cae una instancia?** El health check `/health` (cada 10 s, 2 fallas) la saca del Target Group,
el ALB manda todo a la otra, y el ASG (health check tipo ELB) la reemplaza. Lo demostramos con `prueba-falla.ps1`.

**¿Y si se cae una zona completa?** Hay instancias y subredes en 2 AZ y el ALB está en ambas; el ASG relanza en la AZ sana.

**¿Por qué `/health` no consulta la BD?** Si RDS fallara, el ALB sacaría **todas** las instancias y el servicio
caería por completo. La BD se revisa en `/api/status`.

**¿Para qué la réplica?** Descarga las lecturas (`GET /api/items`) de la primaria y da redundancia de datos en otra AZ.
Si la réplica falla, la app lee de la primaria (`"read_from": "primary (respaldo)"`).

**¿Réplica vs. Multi-AZ?** Multi-AZ es un standby síncrono que no atiende lecturas (failover automático);
la réplica es asíncrona y sí atiende lecturas. Dejamos `db_multi_az` como variable (apagada por costo/tiempo del Learner Lab).

**¿Por qué un solo NAT Gateway?** Costo. Solo afecta la salida a Internet de las instancias (instalación), no el
tráfico de usuarios. En producción: uno por AZ.

**¿Y el almacenamiento? ¿Por qué no hay bucket S3?** El almacenamiento son los discos **EBS gp3 cifrados** de las instancias y el volumen **gp3 cifrado de RDS** (20 GiB, con copias automáticas). Diseñamos también un bucket S3 para los logs de acceso del ALB (está en `main.tf`, variable `enable_alb_access_logs`), pero la política de la organización (SCP) del Learner Lab **niega `s3:GetBucketObjectLockConfiguration`**, operación que el proveedor de Terraform necesita para gestionar cualquier bucket. Lo comprobamos con un bucket de prueba y lo dejamos parametrizado: en una cuenta normal se activa con `true`.

**¿Por qué no HTTPS?** Requiere un dominio propio y un certificado en ACM; el Learner Lab no da dominio. Sería agregar
un listener 443 con el certificado y redirigir 80 → 443.

**¿Cómo se manejan los secretos?** La contraseña de la BD está en `terraform.tfvars` (en `.gitignore`) y marcada `sensitive` (Terraform no la imprime). Terraform la guarda en **SSM Parameter Store como SecureString** (cifrada con KMS) y cada instancia la lee al arrancar **con su rol IAM** (`LabInstanceProfile`): no viaja en el `user_data` ni en el código. Las credenciales de AWS del pipeline están en **GitHub Secrets** (aparecen como `***`). En la instancia, el archivo de configuración tiene permisos 600 del usuario `app`, que no es root.

**¿Por qué Terraform y no la consola?** Reproducible (los 5 integrantes desplegamos lo mismo en 5 cuentas),
versionado en Git, revisable con `plan` antes de cambiar, y se destruye con un comando.

**¿Cómo despliega el pipeline sin downtime?** Con un *rolling update*: termina **una** instancia, el Auto Scaling lanza su reemplazo (que clona el commit nuevo al arrancar) y el pipeline espera a que esté **sano en el ALB** antes de seguir con la siguiente; mientras tanto la otra instancia atiende todo el tráfico. La prueba de humo confirma el commit en todas. Lo implementamos en el pipeline porque la SCP del Learner Lab **niega `autoscaling:StartInstanceRefresh`** (el *instance refresh* nativo de AWS); lo comprobamos con el error exacto.

**¿Qué demuestran las pruebas?** Unitarias (32): lógica de la API y de la capa de datos con dobles de prueba (incluida la reutilización de conexiones)
(caídas de BD, réplica caída, validaciones, pool agotado, IMDSv2). Integración (3): la API real contra
PostgreSQL 16 en el runner. Cobertura ≈ 97 %.

**¿Por qué t3.micro?** Suficiente para la carga del curso y permitida en el Learner Lab; la elasticidad la da el ASG
(escalado horizontal) en vez de instancias grandes (vertical).

**¿Qué es `user_data.sh`?** Script que corre al primer arranque: instala Python 3.11, clona el repo, crea el
entorno virtual, escribe la configuración y registra la API como servicio `systemd` (se reinicia sola si falla).
