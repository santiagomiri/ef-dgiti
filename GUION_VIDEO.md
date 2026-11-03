# Guion del video — Evaluación Final DGITI (máx. 10:00, objetivo 9:30)

Cada bloque dice **qué se ve en pantalla** (🖥️) y **qué se dice** (🎙️). No hay que leerlo palabra por palabra:
apréndanse las ideas y los números. Todo lo que se dice está respaldado por algo que se **ve** en pantalla.

**Regla de oro de cada bloque (15 s, obligatoria):** 🖥️ Canvas → AWS Academy Learner Lab (tarjeta verde) 🟢 con tu nombre →
consola AWS (esquina `voclabs/user...`) → `aws sts get-caller-identity` en PowerShell.
🎙️ "Soy [nombre]. Esta es mi cuenta de AWS Academy, con la sesión activa, y aquí está desplegada nuestra infraestructura."

| Tiempo | Bloque | Criterio (peso) |
|---|---|---|
| 0:00–0:15 | Intro | — |
| 0:15–1:30 | **A. Arquitectura** | 10 % |
| 1:30–3:30 | **B. Infraestructura como Código** | 25 % |
| 3:30–4:45 | **C. Servicio desplegado** | 10 % |
| 4:45–6:45 | **D. Pipeline CI/CD** | 25 % |
| 6:45–9:25 | **E. Desempeño y monitoreo** | 30 % |
| 9:25–9:35 | Cierre | — |

**Preparación coordinada:**
- **~12 min antes** del bloque D: la persona D hace el push `v3` (Guía, Fase C3).
- **~6 min antes** del bloque E: la persona E lanza `k6 ... -e PERFIL=estres` con el dashboard web.
- Si graban cada bloque por separado, igual respeten esos tiempos dentro de su propia grabación y corten la espera.

---

## Intro (0:00–0:15) — cualquiera

🖥️ Diagrama `docs/arquitectura.png` en pantalla completa.
🎙️ "Somos [nombres]. Vamos a demostrar una infraestructura en AWS desplegada con Terraform: un servicio web
detrás de un balanceador de carga, con autoescalado en dos zonas de disponibilidad, base de datos PostgreSQL con
réplica, pipeline CI/CD con pruebas automatizadas, prueba de carga y monitoreo en CloudWatch. Cada uno demuestra
una parte en su propia cuenta de AWS Academy."

---

## A. Arquitectura (0:15–1:30) — 1:15

🖥️ Regla de oro (15 s). Luego el **diagrama**, moviendo el mouse por cada elemento.
🎙️
- "El tráfico sigue el flujo azul: los **usuarios** entran por el **Internet Gateway** al **Application Load
  Balancer**, que está en dos subredes públicas, una por zona de disponibilidad."
- "El ALB reparte las solicitudes entre las **instancias EC2** del **Auto Scaling Group**, que viven en
  **subredes privadas** sin IP pública. Mínimo 2 instancias, una por zona: si se cae una instancia o una zona
  completa, el servicio sigue. Escala hasta 4 cuando la CPU pasa de 50 %."
- "La **base de datos** es RDS PostgreSQL: la primaria recibe escrituras y una **réplica de lectura en la otra
  zona** atiende las lecturas. Están en una tercera capa de subredes **sin ruta a Internet**."
- "La seguridad son **tres Security Groups encadenados**: el del ALB acepta el puerto 80 desde Internet; el de las
  instancias acepta el 8000 **solo desde el ALB**; y el de la base acepta el 5432 **solo desde las instancias**.
  Usamos referencias entre grupos y no IPs, porque con autoescalado las IPs cambian."
- "Las instancias salen a Internet solo por un **NAT Gateway**, para instalar paquetes y bajar el código. Los logs
  del balanceador van a **S3** y las métricas a **CloudWatch**."
- "En verde está el flujo de CI/CD: un push a GitHub dispara GitHub Actions, que prueba, valida y despliega
  reemplazando las instancias de forma gradual."

🖥️ (últimos 15 s) Consola → **VPC → ef-dgiti-vpc → Resource map**.
🎙️ "Y así se ve en mi cuenta: la VPC con sus 6 subredes en dos zonas, sus tablas de rutas, el Internet Gateway y el NAT."

---

## B. Infraestructura como Código (1:30–3:30) — 2:00

🖥️ Regla de oro (15 s). VS Code (o el Bloc de notas) con la carpeta `infra/`.
🎙️ (35 s, mostrando cada archivo)
- "`provider.tf` fija el proveedor AWS 5.x, la región y etiquetas comunes para todos los recursos."
- "`variables.tf` parametriza todo: CIDRs, zonas, tamaño del Auto Scaling, clase de base de datos. La contraseña
  está marcada como `sensitive` y tiene validación."
- "`main.tf` está organizado en 8 secciones: red, security groups, base de datos con réplica, S3, balanceador,
  cómputo con launch template y auto scaling, y monitoreo con dashboard y alarmas."
- "`outputs.tf` entrega la URL del balanceador, los endpoints, y los valores que necesita el pipeline."
- "`terraform.tfvars.example` es la plantilla; el `terraform.tfvars` real tiene la contraseña y **no se sube a Git**."
- "`user_data.sh` es el arranque de cada instancia: instala Python, clona el repositorio, y registra la API como servicio."

🖥️ (15 s) Video del **`terraform apply` inicial acelerado** (de la Fase B4) hasta *Apply complete! Resources: 49 added*.
🎙️ "Este fue el despliegue inicial en mi cuenta: 49 recursos en unos 22 minutos; lo más lento es la réplica de RDS."

🖥️ (55 s) **En vivo** en PowerShell, carpeta `infra`. Primero en `terraform.tfvars` cambia `asg_max_size = 4` por `5`.
```powershell
terraform init
terraform plan
terraform apply
terraform output
```
🎙️
- (init) "`init` descarga el proveedor e inicializa el directorio."
- (plan) "Cambiamos la capacidad máxima del Auto Scaling de 4 a 5. El `plan` compara el estado con la nube y
  muestra **exactamente un cambio en sitio**: `max_size` de 4 a 5; nada se destruye."
- (apply, escribir `yes`) "`apply` lo aplica en segundos."
- (output) "Y `output` nos da la URL del balanceador, los endpoints de validación, los endpoints de RDS y la URL
  del dashboard."

🖥️ (10 s) Consola → **EC2 → Auto Scaling Groups → ef-dgiti-asg**: Max = 5.
🎙️ "En la consola ya se ve el máximo en 5. Así gestionamos los cambios: código, plan, revisión y apply."

> Al terminar la grabación puedes volver a `4` y `terraform apply` (no es obligatorio).

---

## C. Servicio desplegado (3:30–4:45) — 1:15

🖥️ Regla de oro (15 s). Navegador en la URL del ALB.
🎙️ "Este es el servicio a través del DNS del balanceador. La página dice qué instancia y en qué zona la atendió."
🖥️ **F5 tres veces** (cambia instancia y zona).
🎙️ "Al recargar, el balanceador alterna entre la instancia de us-east-1a y la de us-east-1b."

🖥️ (25 s) Pestaña `/docs` (Swagger): **GET /health** → *Try it out* → *Execute* (200). **POST /api/items** con
`{"name": "Demo sustentacion"}` (201, `written_to: primary`). **GET /api/items** (`read_from: replica`, aparece el ítem).
🎙️ "En Swagger validamos los endpoints: `/health` es el que usa el balanceador; el POST escribe en la base
primaria y el GET lee de la réplica de lectura, y ya trae el registro replicado."

🖥️ (10 s) PowerShell: `curl.exe -s "$url/api/status"` (o en el navegador).
🎙️ "`/api/status` confirma las dos bases: la primaria con `is_replica` falso y la réplica con `is_replica`
verdadero y retraso de replicación cero."

🖥️ (20 s) `.\scripts\prueba-falla.ps1` (se puede acelerar en edición).
🎙️ "Ahora simulamos la falla de una instancia: la terminamos mientras consultamos el servicio cada segundo.
Todas las respuestas siguen siendo 200: el balanceador manda todo a la instancia sana, y el Auto Scaling ya está
lanzando el reemplazo, como se ve en su actividad."

---

## D. Pipeline CI/CD (4:45–6:45) — 2:00

🖥️ Regla de oro (15 s). VS Code con `.github/workflows/ci-cd.yml`.
🎙️ (25 s) "El pipeline en GitHub Actions se dispara con cada push a `main` y tiene tres jobs:
uno, **validación de código y pruebas**: lint con ruff, pruebas unitarias con cobertura y pruebas de integración
contra un PostgreSQL real que se levanta como servicio en el runner;
dos, **validación de la infraestructura**: verifica los archivos, `terraform fmt`, `init` y `validate`;
tres, **despliegue**: solo si los dos anteriores pasan."

🖥️ (15 s) GitHub → **Settings → Secrets and variables → Actions**: 3 secretos (valores ocultos) y 3 variables.
🎙️ "Las credenciales de AWS están en **GitHub Secrets**: nunca aparecen en el código ni en los logs; las
variables no sensibles, como el nombre del Auto Scaling Group, están aparte."

🖥️ (15 s) VS Code: el cambio `v3` en `main.py` y en terminal `git log --oneline -1` (el push ya se hizo antes).
🎙️ "Hace unos minutos hicimos este cambio y el push a main, que disparó el pipeline."

🖥️ (35 s) GitHub → **Actions** → el run → grafo de los 3 jobs en verde → job 1: pasos **Pruebas unitarias**
(`32 passed`, tabla de cobertura) y **Pruebas de integración** (`3 passed`) → **Summary** con la tabla de pruebas.
🎙️ "Aquí está la ejecución exitosa. Las 32 pruebas unitarias pasan con 97 % de cobertura: prueban la API y la
capa de datos, incluso escenarios de falla como la réplica caída o la base sin conexión. Las 3 pruebas de
integración corren contra PostgreSQL 16 real: crean y leen datos. Si cualquiera fallara, el despliegue no ocurre."

🖥️ (20 s) Job 3: paso **Rolling update** (líneas `estado=InProgress avance=50%` → `Successful`) y la tabla
del **Summary** (instancia, zona, versión).
🎙️ "El despliegue usa *instance refresh*: reemplaza las instancias de a una, manteniendo al menos 50 % sanas,
así no hay caída. Al final, la prueba de humo consulta el balanceador y verifica que **todas** las instancias
responden el commit nuevo."

🖥️ (10 s) Navegador en la URL del ALB: **"- v3"** y la versión = hash del commit.
🎙️ "Y en el servicio ya está la versión nueva, con el mismo hash del commit."

---

## E. Desempeño y monitoreo (6:45–9:25) — 2:40

> k6 `estres` lanzado ~6 min antes: en este momento está en la fase de 100–200 usuarios.

🖥️ Regla de oro (15 s).
🖥️ (15 s) VS Code con `load-tests/carga.js` (stages y thresholds).
🎙️ "La prueba de carga es con k6. El perfil de estrés sube de 0 a 200 usuarios virtuales en etapas: calentamiento,
carga normal, carga alta, saturación y recuperación. Mezcla un endpoint de CPU, uno liviano y uno que lee la base.
Medimos tiempo de respuesta p50, p95 y p99, el porcentaje de errores, y cuántas respuestas llegan de cada zona."

🖥️ (20 s) Dashboard de k6 en <http://127.0.0.1:5665> (VUs, solicitudes/s, latencia subiendo).
🎙️ "Así va en vivo: [N] usuarios virtuales, unas [X] solicitudes por segundo, y la latencia p95 subió de
[a] a [b] milisegundos: estamos saturando las instancias."

🖥️ (30 s) Consola → **EC2 → Target groups → ef-dgiti-tg → Targets** (instancias healthy + nuevas *initial*/healthy)
y luego **Auto Scaling Groups → ef-dgiti-asg → Activity** (lanzamientos por la alarma de TargetTracking).
🎙️ "Aquí se ve el balanceador operando: reparte entre todas las instancias registradas y sanas. Como la CPU pasó el
objetivo de 50 %, la política de escalado lanzó instancias nuevas: el balanceador las empieza a usar en cuanto
pasan el health check."

🖥️ (45 s) **CloudWatch → Dashboards → ef-dgiti** (rango 1 h, refresh 10 s). Recorrer los widgets:
🎙️
- "Solicitudes al ALB: la rampa de la prueba, hasta [X] por minuto."
- "Tiempo de respuesta: el p95 subió a [b] segundos en la saturación y bajó cuando entraron las instancias nuevas."
- "Códigos HTTP: casi todo 2XX; [ninguno / Y] errores 5XX."
- "CPU: el promedio del grupo superó la línea del objetivo de 50 %, cada instancia llegó a [Z] %."
- "Auto Scaling: deseadas pasó de 2 a [4]."
- "Instancias saludables: de 2 a [4] en el Target Group."
- "Y RDS: CPU y conexiones de primaria y réplica bajas; la base no fue el cuello de botella: lo fue la CPU de las instancias."

🖥️ (25 s) PowerShell: resumen final de k6 (o el **reporte HTML** `load-tests/resultados/reporte-k6.html`).
🎙️ "El resultado: [total] solicitudes, p95 de [b] milisegundos, [Y] % de errores, y las respuestas se
repartieron [A] en us-east-1a y [B] en us-east-1b: el balanceador distribuyó entre las dos zonas."
*(Si se cruzó un umbral:)* "El umbral de p95 se superó en la etapa de 200 usuarios: esa es la evidencia de
saturación de dos t3.micro."

🎙️ (10 s) **Conclusión que relaciona resultados e infraestructura:**
"Con dos t3.micro el servicio aguantó cerca de [N] usuarios con latencia baja; por encima de eso la CPU se
saturó y subió la latencia. El autoescalado reaccionó en unos [M] minutos y la latencia se recuperó. Para
reaccionar más rápido bajaríamos el objetivo de CPU o subiríamos el mínimo de instancias."

---

## Cierre (9:25–9:35) — cualquiera

🖥️ Diagrama.
🎙️ "En resumen: infraestructura reproducible con Terraform, segura por capas, altamente disponible en dos zonas,
desplegada automáticamente con pruebas, y validada bajo carga con métricas en CloudWatch. Gracias."

---

## Evidencias que el profesor busca (marquen al revisar el video)

| Rúbrica | Evidencia en el video | Minuto |
|---|---|---|
| Arquitectura 10 % | Diagrama explicado: red, seguridad, balanceo, HA, cómputo + Resource map | 0:15 |
| IaC 25 % | 6 archivos explicados + `init`, `plan`, `apply`, `output` ejecutados + consola | 1:30 |
| Servicio 10 % | Navegador + Swagger + `/health` + `/api/status` + balanceo + falla de instancia | 3:30 |
| CI/CD 25 % | YAML explicado + secretos + run en verde + pruebas unitarias e integración + despliegue verificado | 4:45 |
| Desempeño 30 % | k6 (VUs, latencia, % errores) + ALB repartiendo + escalado + CloudWatch + conclusión | 6:45 |
| Cuenta propia | Cada integrante muestra su AWS Academy al iniciar su bloque | todos |
