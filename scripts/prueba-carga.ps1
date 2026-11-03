# Prueba de carga con k6 contra el ALB desplegado.
# - Toma la URL del ALB y las instancias en servicio desde Terraform/AWS.
# - Abre el dashboard en vivo de k6 (http://127.0.0.1:5665).
# - Guarda el resumen (texto) y el reporte HTML en load-tests\resultados\.
# Uso (desde la raiz del repo):  .\scripts\prueba-carga.ps1               (perfil estres)
#                                .\scripts\prueba-carga.ps1 -Perfil humo
param(
    [ValidateSet("humo", "carga", "estres")]
    [string]$Perfil = "estres",
    [int]$Iteraciones = 20000
)

$raiz = Split-Path $PSScriptRoot -Parent
Set-Location $raiz
$url = terraform -chdir=infra output -raw alb_url
$asg = terraform -chdir=infra output -raw asg_name
$ids = aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names $asg `
    --query "AutoScalingGroups[0].Instances[?LifecycleState=='InService'].InstanceId" --output text
$instancias = (($ids -split "\s+") | Where-Object { $_ }) -join ","

$dir = Join-Path $raiz "load-tests\resultados"
New-Item -ItemType Directory -Force $dir | Out-Null
$marca = Get-Date -Format "yyyyMMdd-HHmm"
$env:K6_WEB_DASHBOARD = "true"
$env:K6_WEB_DASHBOARD_EXPORT = "load-tests/resultados/reporte-k6-$Perfil-$marca.html"

Write-Host "ALB:         $url" -ForegroundColor Cyan
Write-Host "Instancias:  $instancias" -ForegroundColor Cyan
Write-Host "Perfil:      $Perfil   (dashboard en vivo: http://127.0.0.1:5665)" -ForegroundColor Cyan
Write-Host "Inicio:      $(Get-Date -Format 'HH:mm:ss')`n" -ForegroundColor Cyan

k6 run -e BASE_URL=$url -e PERFIL=$Perfil -e ITERACIONES=$Iteraciones -e INSTANCIAS=$instancias `
    load-tests/carga.js | Tee-Object -FilePath (Join-Path $dir "resumen-k6-$Perfil-$marca.txt")

Write-Host "`nFin: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Cyan
Write-Host "Reporte HTML: load-tests\resultados\reporte-k6-$Perfil-$marca.html" -ForegroundColor Green
Write-Host "Resumen:      load-tests\resultados\resumen-k6-$Perfil-$marca.txt" -ForegroundColor Green
