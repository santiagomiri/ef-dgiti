# Resultados de la prueba de carga

Ejecutada el 3 de noviembre de 2026 (15:00–15:10, hora de Colombia) contra el ALB desplegado en la cuenta de AWS
Academy Learner Lab, con `.\scripts\prueba-carga.ps1` (perfil `estres`: rampa de 0 a 200 usuarios virtuales y
meseta, ~10,5 minutos). Evidencia en el repositorio: [`docs/evidencias/reporte-k6-estres-referencia.html`](../docs/evidencias/reporte-k6-estres-referencia.html)
(dashboard de k6 exportado) y [`docs/evidencias/resumen-k6-estres-referencia.txt`](../docs/evidencias/resumen-k6-estres-referencia.txt).

## Resumen de k6

| Métrica | Resultado | Umbral | |
|---|---|---|---|
| Usuarios virtuales máximos | 200 | — | |
| Solicitudes totales | 125 736 (199/s) | — | |
| Tiempo de respuesta p50 / p90 / p95 / p99 | 155 ms / 719 ms / 841 ms / 1,02 s | p95 < 2 s | ✅ |
| p95 por endpoint (compute / info / items) | 858 ms / 765 ms / 911 ms | < 3 s / 1,5 s / 2 s | ✅ |
| Porcentaje de errores | 0,02 % (27 de 125 736) | < 5 % | ✅ |
| Respuestas por zona (us-east-1a / us-east-1b) | 62 403 / 63 305 (49,6 % / 50,4 %) | > 0 cada una | ✅ |
| Respuestas de las 2 instancias iniciales | 47 953 / 47 938 | > 0 cada una | ✅ |
| Respuestas de las 2 instancias lanzadas por el escalado | ~29 800 (24 %) | — | |

## Comportamiento minuto a minuto (CloudWatch)

| Hora | Instancias sanas en el ALB | CPU promedio del ASG | Solicitudes/min | Latencia p95 (ALB) |
|---|---|---|---|---|
| 15:02 | 2 | 59 % | 11 109 | 399 ms |
| 15:03 | 2 | 85 % | 11 908 | 850 ms |
| 15:04 | 2 | 87 % | 11 524 | 867 ms |
| 15:05 | 2 | 83 % | 11 446 | 878 ms |
| 15:06 | 4 | 84 % | 12 460 | 869 ms |
| 15:07 | 4 | 55 % | 18 859 | 93 ms |
| 15:08 | 4 | 52 % | 18 813 | 100 ms |
| 15:09 | 4 | 52 % | 18 130 | 100 ms |

- CPU máxima de RDS durante la prueba: primaria 8,6 %, réplica 5,5 %.
- Alarmas al terminar: las 4 en `OK`.

## Relación con la infraestructura

1. **Saturación:** con 2 instancias `t3.micro` (2 vCPU cada una) la CPU llegó al 85–87 % y la latencia p95 subió de
   ~30 ms en reposo a ~870 ms. El endpoint `/api/compute`, que tarda 13 ms con el servidor libre, llegó a 221 ms (p95)
   medido dentro de la propia instancia: el cuello de botella fue la **CPU de las instancias**.
2. **Escalado automático:** la política de *target tracking* (CPU promedio 50 %) necesita 3 minutos seguidos por encima
   del objetivo; el ASG pasó de 2 a 4 instancias al minuto 5 de la prueba y las nuevas quedaron sanas en el ALB al
   minuto 7 (~2 minutos de arranque: instalación de Python, clonado del repositorio y health check).
3. **Efecto del escalado:** con 4 instancias el sistema atendió **60 % más solicitudes por minuto** (de ~11 500 a
   ~18 800) con la CPU en ~52 % (cerca del objetivo de 50 %) y la latencia p95 bajó **9 veces** (de ~870 ms a ~100 ms).
4. **Balanceador:** el ALB repartió el tráfico 50/50 entre zonas y entre las instancias iniciales, y empezó a enviar
   tráfico a las instancias nuevas en cuanto pasaron el health check `/health`.
5. **Base de datos:** RDS no superó el 9 % de CPU; la réplica de lectura absorbió las consultas de `/api/items`.
6. **Errores:** 27 respuestas 5XX del ALB (0,02 %), muy por debajo del umbral de 5 %.

**Mejoras posibles:** reaccionar antes bajando el objetivo de CPU (p. ej. 40 %) o subiendo el mínimo a 3 instancias;
reducir el arranque con una AMI preconstruida (Packer) que ya traiga Python y las dependencias.
