# Guion del video — Evaluación Final DGITI (1 integrante · máx. 10:00 · objetivo 9:30)

Presentas tú solo los 5 bloques, todos en **tu** cuenta de AWS Academy Learner Lab.
Cada bloque indica **qué se ve en pantalla** (🖥️) y **qué se dice** (🎙️). No lo leas palabra por palabra:
apréndete las ideas y los números. Todo lo que dices se respalda con algo que se **ve**.

## Cómo grabar (recomendado para una sola persona)

Graba **por bloques** (un clip por bloque) y luego únelos en **Clipchamp** (viene con Windows).
Así puedes repetir un bloque si te equivocas y **cortar las esperas** (despliegue del pipeline, escalado).

- **Aparece en cámara** (recomendado: es la evidencia más clara de que eres tú quien demuestra en vivo):
  en **Clipchamp → Grabar → Pantalla y cámara**, o con **OBS Studio** (cámara en una esquina).
  Si no tienes cámara: **Windows + Alt + R** (Xbox Game Bar) graba la pantalla con tu voz.
- Antes de grabar: `.\scripts\verificar-todo.ps1` debe terminar en **TODO LISTO**.
- Letra grande en PowerShell (Ctrl + rueda del mouse), navegador al 125 %, notificaciones apagadas.
- **Nunca** mostrar `terraform.tfvars`, `~\.aws\credentials` ni AWS Details con las claves.

| Clip | Bloque | Criterio (peso) | Duración |
|---|---|---|---|
| 1 | Intro + **A. Arquitectura** | 10 % | 0:00–1:30 |
| 2 | **B. Infraestructura como Código** | 25 % | 1:30–3:30 |
| 3 | **C. Servicio desplegado** | 10 % | 3:30–4:45 |
| 4 | **D. Pipeline CI/CD** | 25 % | 4:45–6:45 |
| 5 | **E. Desempeño y monitoreo** | 30 % | 6:45–9:25 |
| 6 | Cierre | — | 9:25–9:35 |

---

## Clip 1 — Intro + A. Arquitectura (0:00–1:30)

🖥️ **Evidencia de cuenta propia (15 s, obligatorio):** Canvas → tarjeta verde **AWS Academy Learner Lab**
→ página del lab con tu nombre y el 🟢 → abrir la consola AWS (esquina superior derecha `voclabs/user...`)
→ PowerShell: `aws sts get-caller-identity`.
🎙️ "Soy [tu nombre completo]. Esta es mi cuenta de AWS Academy Learner Lab, con la sesión activa. Voy a demostrar
una infraestructura en AWS desplegada con Terraform: un servicio web detrás de un balanceador de carga, con
autoescalado en dos zonas de disponibilidad, base de datos PostgreSQL con réplica, pipeline CI/CD con pruebas
automatizadas, prueba de carga y monitoreo en CloudWatch."

🖥️ `docs/arquitectura.png` en pantalla completa; mueve el mouse por cada elemento.
🎙️
- "El tráfico sigue el flujo azul: los **usuarios** entran por el **Internet Gateway** al **Application Load
  Balancer**, que está en dos subredes públicas, una por zona de disponibilidad."
- "El ALB reparte las solicitudes entre las **instancias EC2** del **Auto Scaling Group**, en **subredes privadas**
  sin IP pública. Mínimo 2 instancias, una por zona: si se cae una instancia o una zona, el servicio sigue.
  Escala hasta 4 cuando la CPU pasa de 50 %."
- "La **base de datos** es RDS PostgreSQL: la primaria recibe escrituras y una **réplica de lectura en la otra zona**
  atiende las lecturas, en una tercera capa de subredes **sin ruta a Internet**."
- "La seguridad son **tres Security Groups encadenados**: el del ALB acepta el puerto 80 desde Internet; el de las
  instancias acepta el 8000 **solo desde el ALB**; y el de la base acepta el 5432 **solo desde las instancias**.
  Uso referencias entre grupos y no IPs, porque con autoescalado las IPs cambian."
- "Las instancias salen a Internet solo por un **NAT Gateway**. Los discos EBS y el almacenamiento de RDS van
  **cifrados**, y las métricas van a **CloudWatch**."
- "**Decisiones de cómputo:** EC2 **t3.micro** con **Amazon Linux 2023** en un Auto Scaling Group. Prefiero escalar
  **horizontalmente** (más instancias pequeñas detrás del balanceador) que verticalmente (una instancia grande):
  da tolerancia a fallos y elasticidad. El Launch Template exige **IMDSv2** y cifra el disco, y la API corre como
  servicio **systemd** con un usuario sin privilegios, con 2 procesos por instancia (una por vCPU)."
- "**Alta disponibilidad:** todo está duplicado en dos zonas: subredes públicas, instancias y base de datos
  (primaria en 1a, réplica en 1b). El balanceador revisa `/health` cada 10 segundos: si una instancia falla dos
  veces la saca del tráfico, y el Auto Scaling la reemplaza automáticamente."
- "En verde está el CI/CD: un push a GitHub dispara GitHub Actions, que prueba, valida y despliega reemplazando las
  instancias de forma gradual."

🖥️ (15 s) Consola → **VPC → Your VPCs → ef-dgiti-vpc → pestaña Resource map**.
🎙️ "Y así se ve desplegado en mi cuenta: la VPC con sus 6 subredes en dos zonas, las tablas de rutas, el Internet
Gateway y el NAT."

---

## Clip 2 — B. Infraestructura como Código (1:30–3:30)

🖥️ (35 s) VS Code o el Bloc de notas con la carpeta `infra/`, mostrando cada archivo.
🎙️
- "`provider.tf` fija el proveedor AWS 5.x, la región y etiquetas comunes para todos los recursos."
- "`variables.tf` parametriza todo: CIDRs, zonas, tamaño del Auto Scaling, clase de base de datos. La contraseña está
  marcada como `sensitive` y tiene validación."
- "`main.tf` está organizado en 8 secciones: red, security groups, base de datos con réplica, almacenamiento,
  balanceador, cómputo con launch template y auto scaling, y monitoreo con dashboard y alarmas."
- "`outputs.tf` entrega la URL del balanceador, los endpoints y los valores que necesita el pipeline."
- "`terraform.tfvars.example` es la plantilla; el `terraform.tfvars` real tiene la contraseña y **no se sube a Git**."
- "`user_data.sh` es el arranque de cada instancia: instala Python, clona el repositorio, **lee la contraseña de la base
  desde SSM Parameter Store cifrada con KMS usando el rol IAM de la instancia** (así la contraseña nunca viaja en el
  user_data ni en el código) y registra la API como servicio."

🖥️ (15 s) En PowerShell (carpeta `infra`): `terraform state list` (se ve la lista completa de recursos).
🎙️ "Este es el estado de Terraform en mi cuenta: 45 recursos gestionados. El despliegue inicial tomó unos 20
minutos; lo más lento es la réplica de RDS."

🖥️ (55 s) **En vivo** en PowerShell, carpeta `infra`. Antes, en `terraform.tfvars` cambia `asg_max_size = 4` por `5`
(o agrega la línea si no está).
```powershell
terraform init
terraform plan
terraform apply
terraform output
```
🎙️
- (init) "`init` descarga el proveedor e inicializa el directorio."
- (plan) "Subo la capacidad máxima del Auto Scaling de 4 a 5. El `plan` compara el estado con la nube y muestra
  **un solo cambio en sitio**: `max_size` de 4 a 5; nada se destruye."
- (apply, escribes `yes` y Enter) "`apply` lo aplica en segundos."
- (output) "`output` entrega la URL del balanceador, los endpoints de validación, los de RDS y la URL del dashboard."

🖥️ (10 s) Consola → **EC2 → Auto Scaling Groups → ef-dgiti-asg**: Max = 5.
🎙️ "En la consola ya se ve el máximo en 5. Así gestiono los cambios: código, plan, revisión y apply."

---

## Clip 3 — C. Servicio desplegado (3:30–4:45)

🖥️ Navegador en la URL del ALB (`terraform output -raw alb_url`). **F5 tres veces.**
🎙️ "Este es el servicio a través del DNS del balanceador. La página dice qué instancia y en qué zona me atendió; al
recargar, el balanceador alterna entre la instancia de us-east-1a y la de us-east-1b."

🖥️ (25 s) Pestaña `/docs` (Swagger): **GET /health** → *Try it out* → *Execute* (200). **POST /api/items** con
`{"name": "Demo sustentacion"}` (201, `written_to: primary`). **GET /api/items** (`read_from: replica`).
🎙️ "En Swagger valido los endpoints: `/health` es el que usa el balanceador; el POST escribe en la base primaria y el
GET lee de la réplica de lectura, y ya trae el registro replicado."

🖥️ (10 s) `/api/status` en el navegador.
🎙️ "`/api/status` confirma las dos bases: la primaria con `is_replica` falso y la réplica con `is_replica` verdadero."

🖥️ (20 s) `.\scripts\prueba-falla.ps1` (acelera la parte de espera en la edición).
🎙️ "Ahora simulo la falla de una instancia: la termino mientras consulto el servicio cada segundo. Todas las
respuestas siguen en 200: el balanceador manda todo a la instancia sana, y el Auto Scaling lanza el reemplazo, como
se ve en su actividad."

---

## Clip 4 — D. Pipeline CI/CD (4:45–6:45)

> **Antes de grabar este clip:** haz el cambio `v3` (en `app/main.py` cambia el `<h1>`), `git commit` y `git push`,
> y espera ~10 min a que el run termine. Graba mostrando el run ya terminado.

🖥️ (25 s) VS Code con `.github/workflows/ci-cd.yml`.
🎙️ "El pipeline en GitHub Actions se dispara con cada push a `main` y tiene tres jobs: uno, **validación de código y
pruebas**: lint con ruff, pruebas unitarias con cobertura y pruebas de integración contra un PostgreSQL real que se
levanta en el runner; dos, **validación de la infraestructura**: archivos requeridos, `terraform fmt`, `init` y
`validate`; tres, **despliegue**: solo si los dos anteriores pasan."

🖥️ (15 s) GitHub → **Settings → Secrets and variables → Actions**: 3 secretos (valores ocultos) y 3 variables.
🎙️ "Las credenciales de AWS están en **GitHub Secrets**: nunca aparecen en el código ni en los logs."

🖥️ (35 s) GitHub → **Actions** → el run del commit v3 → grafo de los 3 jobs en verde → job 1: pasos **Pruebas
unitarias** (`32 passed`, cobertura) y **Pruebas de integración** (`3 passed`) → **Summary** con la tabla de pruebas.
🎙️ "Aquí está la ejecución exitosa. Las 32 pruebas unitarias pasan con 97 % de cobertura: prueban la API y la capa
de datos, incluso escenarios de falla como la réplica caída o la base sin conexión. Las 3 pruebas de integración
corren contra PostgreSQL 16 real. Si cualquiera fallara, el despliegue no ocurre."

🖥️ (25 s) Job 3: paso **Rolling update** (abre los grupos "Reemplazando i-..." con las líneas `instancias sanas sin i-...: 2 de 2`) y la tabla del **Summary** con instancia, zona y versión.
🎙️ "El despliegue es un *rolling update*: termina una instancia, el Auto Scaling lanza su reemplazo con el código nuevo,
y el pipeline espera a que esté sana en el balanceador antes de seguir con la otra; mientras tanto la otra instancia
atiende todo el tráfico, así
no hay caída. La prueba de humo verifica que **todas** las instancias responden el commit nuevo."

🖥️ (10 s) Navegador en la URL del ALB: **"- v3"** y la versión = hash del commit.
🎙️ "Y el servicio ya muestra la versión nueva, con el mismo hash del commit."

---

## Clip 5 — E. Desempeño y monitoreo (6:45–9:25)

> **Cómo grabarlo:** lanza la prueba (paso 1), graba la explicación, **pausa la grabación** y reanuda a los
> ~5 minutos, cuando CloudWatch ya muestre el escalado.

🖥️ (15 s) VS Code con `load-tests/carga.js` (stages y thresholds).
🎙️ "La prueba de carga es con k6. El perfil de estrés sube de 0 a 200 usuarios virtuales: calentamiento, carga
normal, carga alta, saturación y recuperación. Mide tiempo de respuesta p50, p95 y p99, el porcentaje de errores y
cuántas respuestas llegan de cada zona."

🖥️ (10 s) Lanzar la prueba en PowerShell (raíz del repo):
```powershell
.\scripts\prueba-carga.ps1
```
🎙️ "El script toma la URL del balanceador y las instancias en servicio, abre el dashboard en vivo de k6 y guarda
el resumen y un reporte HTML como evidencia."

🖥️ (20 s) Dashboard de k6 en <http://127.0.0.1:5665> (usuarios virtuales, solicitudes/s, latencia).
🎙️ "En vivo: [N] usuarios virtuales, unas [X] solicitudes por segundo, y la latencia p95 subió de [a] a [b]
milisegundos: estoy saturando las instancias."

🖥️ (30 s) Consola → **EC2 → Target groups → ef-dgiti-tg → Targets** (instancias sanas + nuevas) y luego
**Auto Scaling Groups → ef-dgiti-asg → Activity** (lanzamientos por la alarma de TargetTracking).
🎙️ "Aquí se ve el balanceador operando: reparte entre todas las instancias sanas. Como la CPU superó el objetivo de
50 %, la política de escalado lanzó instancias nuevas, y el balanceador las usa en cuanto pasan el health check."

🖥️ (45 s) **CloudWatch → Dashboards → ef-dgiti** (rango 1 h, actualización 10 s). Recorre los widgets:
🎙️
- "Solicitudes al ALB: la rampa de la prueba, hasta [X] por minuto."
- "Tiempo de respuesta: el p95 subió a [b] en la saturación y bajó cuando entraron las instancias nuevas."
- "Códigos HTTP: casi todo 2XX; [ningún / Y] error 5XX."
- "CPU: el promedio superó la línea del objetivo de 50 %; cada instancia llegó a [Z] %."
- "Auto Scaling: las instancias deseadas pasaron de 2 a [4]."
- "Instancias saludables en el Target Group: de 2 a [4]."
- "RDS: CPU y conexiones bajas en primaria y réplica: el cuello de botella fue la CPU de las instancias, no la base."

🖥️ (25 s) Resumen final de k6 en PowerShell (o el reporte `load-tests/resultados/reporte-k6.html`).
🎙️ "Resultado: [total] solicitudes, p95 de [b] milisegundos, [Y] % de errores. Mira `respuestas_por_instancia`:
la instancia [i-...] atendió [A] y la [i-...] atendió [B], y por zona [A] en us-east-1a y [B] en us-east-1b:
el balanceador repartió el tráfico casi en partes iguales."
*(Si se cruzó un umbral:)* "El umbral de p95 se superó en la etapa de 200 usuarios: esa es la evidencia de
saturación de dos t3.micro."

🎙️ (10 s) **Conclusión que relaciona resultados e infraestructura:** "Con dos t3.micro el servicio aguantó cerca de
[N] usuarios con baja latencia; por encima se saturó la CPU y subió la latencia. El autoescalado reaccionó en unos
[M] minutos y la latencia se recuperó. Para reaccionar más rápido bajaría el objetivo de CPU o subiría el mínimo de
instancias."

---

## Clip 6 — Cierre (9:25–9:35)

🖥️ Diagrama.
🎙️ "En resumen: infraestructura reproducible con Terraform, segura por capas, altamente disponible en dos zonas,
desplegada automáticamente con pruebas y validada bajo carga con métricas en CloudWatch. Gracias."

---

## Evidencias que busca el profesor (revisa el video final con esta tabla)

| Rúbrica | Evidencia en el video | Minuto |
|---|---|---|
| Cuenta propia | Learner Lab con tu nombre + consola + `get-caller-identity` | 0:00 |
| Arquitectura 10 % | Diagrama explicado: red, seguridad, balanceo, HA, cómputo + Resource map | 0:15 |
| IaC 25 % | 6 archivos explicados + `init`, `plan`, `apply`, `output` en vivo + consola | 1:30 |
| Servicio 10 % | Navegador + Swagger + `/health` + `/api/status` + balanceo + falla de instancia | 3:30 |
| CI/CD 25 % | YAML explicado + secretos + run en verde + pruebas unitarias e integración + despliegue verificado | 4:45 |
| Desempeño 30 % | k6 (VUs, latencia, % errores) + ALB repartiendo + escalado + CloudWatch + conclusión | 6:45 |
