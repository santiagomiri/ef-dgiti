# Demostracion del pipeline CI/CD para el video (clip 4), paso a paso con Enter.
# Cambia el titulo de la pagina a "v3", hace commit y push, y abre GitHub Actions.
# Uso (desde la raiz del repo):  .\scripts\demo-cicd.ps1

$raiz = Split-Path $PSScriptRoot -Parent
Set-Location $raiz

function Paso($n, $titulo, $texto, [scriptblock]$accion) {
    Write-Host ""
    Write-Host "=== PASO $n de 4: $titulo ===" -ForegroundColor Cyan
    Read-Host "Presiona Enter para ejecutar" | Out-Null
    Write-Host "PS> $texto" -ForegroundColor Yellow
    & $accion
}

# Siguiente version del titulo: sin version -> v3; "- vN" -> "- v(N+1)"
$f = Join-Path $raiz "app\main.py"
$t = [IO.File]::ReadAllText($f)
if ($t -match "<h1>Evaluacion Final DGITI - v(\d+)</h1>") { $actual = $Matches[0]; $v = [int]$Matches[1] + 1 }
else { $actual = "<h1>Evaluacion Final DGITI</h1>"; $v = 3 }
$nuevo = "<h1>Evaluacion Final DGITI - v$v</h1>"

Paso 1 "Cambio visible en la pagina: titulo v$v" "app/main.py: $nuevo" {
    [IO.File]::WriteAllText($f, $t.Replace($actual, $nuevo), (New-Object Text.UTF8Encoding($false)))
    git --no-pager diff --color=always app/main.py
}

Paso 2 "Commit" "git add app/main.py; git commit -m 'Pagina version $v'" {
    git add app/main.py
    git commit -m "Pagina version $v"
}

Paso 3 "Push a main (dispara el pipeline)" "git push" { git push }

Paso 4 "Abrir GitHub Actions" "start https://github.com/santiagomiri/ef-dgiti/actions" {
    Start-Process msedge "https://github.com/santiagomiri/ef-dgiti/actions"
}

Write-Host ""
Write-Host "LISTO. Deja grabando la pagina de Actions hasta que los 3 jobs queden en verde." -ForegroundColor Green
