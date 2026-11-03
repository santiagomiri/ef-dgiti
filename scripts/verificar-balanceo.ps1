# Envia N solicitudes al ALB y cuenta cuantas atendio cada instancia.
# Uso (desde la raiz del repo):  .\scripts\verificar-balanceo.ps1
#                                .\scripts\verificar-balanceo.ps1 -Solicitudes 40
param(
    [string]$Url = "",
    [int]$Solicitudes = 20
)

if (-not $Url) { $Url = terraform -chdir=infra output -raw alb_url }
Write-Host "ALB: $Url  ($Solicitudes solicitudes a /api/info)`n" -ForegroundColor Cyan

$resultados = @()
for ($i = 1; $i -le $Solicitudes; $i++) {
    try {
        $r = Invoke-RestMethod -Uri "$Url/api/info" -TimeoutSec 10
        "{0,3}  {1,-21} {2,-12} version {3}" -f $i, $r.instance_id, $r.availability_zone, $r.version | Write-Host
        $resultados += [pscustomobject]@{ Instancia = $r.instance_id; Zona = $r.availability_zone }
    } catch {
        Write-Host ("{0,3}  ERROR: {1}" -f $i, $_.Exception.Message) -ForegroundColor Red
    }
}

Write-Host "`nReparto del balanceador:" -ForegroundColor Cyan
$resultados | Group-Object Instancia, Zona | Sort-Object Name |
    Select-Object @{n = "Instancia / Zona"; e = { $_.Name } }, @{n = "Solicitudes"; e = { $_.Count } },
                  @{n = "Porcentaje"; e = { "{0:P0}" -f ($_.Count / $Solicitudes) } } |
    Format-Table -AutoSize
