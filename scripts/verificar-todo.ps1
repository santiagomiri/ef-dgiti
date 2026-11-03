# Verificacion previa: correr ANTES de desplegar y ANTES de grabar.
# Uso (desde la raiz del repo):  .\scripts\verificar-todo.ps1
# Verde = listo. Rojo = corregir (el mensaje dice como).

$ErrorActionPreference = "Continue"
$fallas = 0
function Ok($m)    { Write-Host "  [OK]    $m" -ForegroundColor Green }
function Mal($m)   { Write-Host "  [FALLA] $m" -ForegroundColor Red; $script:fallas++ }
function Aviso($m) { Write-Host "  [AVISO] $m" -ForegroundColor Yellow }
function Titulo($t){ Write-Host "`n== $t" -ForegroundColor Cyan }

$raiz = Split-Path $PSScriptRoot -Parent
Set-Location $raiz

Titulo "1. Herramientas"
foreach ($h in @(
    @{ n = "git"; c = { git --version } },
    @{ n = "terraform"; c = { terraform version | Select-Object -First 1 } },
    @{ n = "aws"; c = { aws --version } },
    @{ n = "k6"; c = { k6 version } })) {
    if (Get-Command $h.n -ErrorAction SilentlyContinue) { Ok ("{0}: {1}" -f $h.n, (& $h.c 2>&1 | Out-String).Trim()) }
    else { Mal "$($h.n) no esta instalado (ver GUIA seccion 3.1)" }
}

Titulo "2. Credenciales de AWS Academy"
$arn = aws sts get-caller-identity --query Arn --output text 2>$null
if ($LASTEXITCODE -eq 0 -and $arn) { Ok "Sesion valida: $arn" }
else { Mal "Credenciales vencidas o ausentes: Start Lab y .\scripts\credenciales.ps1 (GUIA paso B2)" }
$region = aws configure get region 2>$null
if ($region -and $region -ne "us-east-1") { Aviso "Region del CLI = $region (Terraform usa us-east-1 de terraform.tfvars)" }

Titulo "3. terraform.tfvars"
$tfvars = Join-Path $raiz "infra\terraform.tfvars"
$repoUrl = $null
if (-not (Test-Path $tfvars)) { Mal "No existe infra\terraform.tfvars (GUIA paso B3)" }
else {
    $contenido = Get-Content $tfvars -Raw
    if ($contenido -match 'app_repo_url\s*=\s*"([^"]+)"') { $repoUrl = $Matches[1] }
    if (-not $repoUrl -or $repoUrl -match "USUARIO") { Mal "app_repo_url no esta configurado con el repo real del grupo" }
    else { Ok "app_repo_url = $repoUrl" }
    if ($contenido -match 'db_password\s*=\s*"([^"]+)"') {
        $clave = $Matches[1]
        if ($clave -eq "CambiarEstaClave2026") { Mal "db_password sigue con el valor de ejemplo: cambialo" }
        elseif ($clave -cmatch '^[A-Za-z0-9]{12,40}$') { Ok "db_password cumple la regla (12-40 letras/numeros)" }
        else { Mal "db_password debe tener 12 a 40 caracteres, solo letras y numeros" }
    } else { Mal "Falta db_password en terraform.tfvars" }
}

Titulo "4. Repositorio publico en GitHub (las instancias lo clonan sin credenciales)"
if ($repoUrl) {
    $env:GIT_TERMINAL_PROMPT = "0"
    $ref = git -c credential.helper= ls-remote $repoUrl refs/heads/main 2>$null
    if ($LASTEXITCODE -eq 0 -and $ref) { Ok "El repo es publico y tiene la rama main ($($ref.Substring(0,7)))" }
    else { Mal "No se puede clonar $repoUrl sin credenciales: el repo debe ser PUBLICO y tener la rama main" }
}

Titulo "5. Codigo Terraform"
Push-Location infra
terraform fmt -check -recursive *> $null
if ($LASTEXITCODE -eq 0) { Ok "terraform fmt sin cambios pendientes" } else { Mal "terraform fmt encontro archivos sin formato: corre 'terraform fmt'" }
if (Test-Path ".terraform") {
    terraform validate -no-color *> $null
    if ($LASTEXITCODE -eq 0) { Ok "terraform validate: configuracion valida" } else { Mal "terraform validate fallo: corre 'terraform validate' para ver el error" }
} else { Aviso "Aun no se ha corrido 'terraform init' en infra (normal antes del primer despliegue)" }

Titulo "6. Despliegue (si ya hiciste terraform apply)"
$url = terraform output -raw alb_url 2>$null
if ($LASTEXITCODE -ne 0 -or -not $url -or $url -notmatch "^http") {
    Aviso "No hay despliegue registrado en este PC (normal antes del apply)"
} else {
    Ok "ALB: $url"
    try {
        $h = Invoke-RestMethod "$url/health" -TimeoutSec 10
        Ok "/health -> $($h.status) (instancia $($h.instance_id), zona $($h.availability_zone), version $($h.version))"
    } catch { Mal "/health no responde: si el apply fue hace menos de 5 min, espera; si no, GUIA seccion 11 problema 4" }
    try {
        $s = Invoke-RestMethod "$url/api/status" -TimeoutSec 15
        if ($s.status -eq "ok" -and -not $s.database.primary.is_replica -and $s.database.replica.is_replica) {
            Ok "/api/status -> ok: primaria (escritura) y replica (is_replica=true) conectadas"
        } else { Aviso "/api/status -> $($s.status) (la replica puede estar iniciando)" }
    } catch { Mal "/api/status no responde" }
    $tg = terraform output -raw target_group_arn 2>$null
    if ($tg -and $arn) {
        # El Target Group no informa la zona de destinos tipo instancia: se consulta en EC2
        $ids = aws elbv2 describe-target-health --target-group-arn $tg `
            --query "TargetHealthDescriptions[?TargetHealth.State=='healthy'].Target.Id" --output text 2>$null
        $sanas = @(($ids -split "\s+") | Where-Object { $_ })
        $zonas = @()
        if ($sanas.Count -gt 0) {
            $zonas = @((aws ec2 describe-instances --instance-ids $sanas `
                --query "Reservations[].Instances[].Placement.AvailabilityZone" --output text 2>$null) -split "\s+" |
                Where-Object { $_ } | Sort-Object -Unique)
        }
        if ($sanas.Count -ge 2 -and $zonas.Count -ge 2) { Ok "Target Group: $($sanas.Count) instancias sanas en $($zonas.Count) zonas ($($zonas -join ', '))" }
        else { Mal "Target Group: $($sanas.Count) instancias sanas en $($zonas.Count) zona(s); se esperan >= 2 en 2 zonas" }
    }
    $plan = terraform plan -detailed-exitcode -input=false -lock=false -no-color 2>&1
    switch ($LASTEXITCODE) {
        0 { Ok "terraform plan: No changes (la nube coincide con el codigo)" }
        2 { Aviso "terraform plan detecta cambios pendientes: revisa con 'terraform plan'" }
        default { Mal "terraform plan fallo: $(($plan | Select-String 'Error' | Select-Object -First 1))" }
    }
}
Pop-Location

Write-Host ""
if ($fallas -eq 0) { Write-Host "TODO LISTO" -ForegroundColor Green }
else { Write-Host "$fallas problema(s) por corregir (ver mensajes en rojo)" -ForegroundColor Red }
