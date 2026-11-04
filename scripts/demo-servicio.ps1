# Demostracion del servicio para el video (clip 3), paso a paso con Enter.
# Valida los endpoints a traves del balanceador y termina con la prueba de falla.
# Uso (desde la raiz del repo):  .\scripts\demo-servicio.ps1

$raiz = Split-Path $PSScriptRoot -Parent
Set-Location $raiz
$url = terraform -chdir=infra output -raw alb_url

function Paso($n, $titulo, $metodo, $ruta, $cuerpo) {
    Write-Host ""
    Write-Host "=== PASO $n de 5: $titulo ===" -ForegroundColor Cyan
    Read-Host "Presiona Enter para ejecutar" | Out-Null
    Write-Host "$metodo $url$ruta" -ForegroundColor Yellow
    if ($cuerpo) { Write-Host "Cuerpo: $cuerpo" -ForegroundColor Yellow }
    $p = @{ Uri = "$url$ruta"; Method = $metodo; UseBasicParsing = $true; TimeoutSec = 15 }
    if ($cuerpo) { $p.Body = $cuerpo; $p.ContentType = "application/json" }
    try {
        $r = Invoke-WebRequest @p
        Write-Host "HTTP $($r.StatusCode)" -ForegroundColor Green
        $r.Content | ConvertFrom-Json | ConvertTo-Json -Depth 6
    } catch {
        Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Paso 1 "Salud del servicio (lo usa el balanceador)" "GET" "/health" $null
Paso 2 "Escribir un dato (va a la base principal)" "POST" "/api/items" '{"name": "Demo sustentacion"}'
Paso 3 "Leer los datos (vienen de la replica)" "GET" "/api/items" $null
Paso 4 "Estado de las dos bases de datos" "GET" "/api/status" $null

Write-Host ""
Write-Host "=== PASO 5 de 5: Simular la falla de un servidor ===" -ForegroundColor Cyan
Read-Host "Presiona Enter para ejecutar" | Out-Null
& (Join-Path $PSScriptRoot "prueba-falla.ps1")

Write-Host ""
Write-Host "LISTO." -ForegroundColor Green
