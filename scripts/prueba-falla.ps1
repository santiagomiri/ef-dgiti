# Prueba de alta disponibilidad: termina UNA instancia del Auto Scaling Group
# mientras se consulta el servicio cada segundo. El servicio debe seguir
# respondiendo (la otra instancia atiende) y el ASG lanza un reemplazo.
# Uso (desde la raiz del repo):  .\scripts\prueba-falla.ps1
param(
    [int]$Segundos = 45
)

$url = terraform -chdir=infra output -raw alb_url
$asg = terraform -chdir=infra output -raw asg_name

$ids = aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names $asg `
    --query "AutoScalingGroups[0].Instances[?LifecycleState=='InService'].InstanceId" --output text
$victima = ($ids -split "\s+" | Where-Object { $_ })[0]
if (-not $victima) { Write-Host "No hay instancias en servicio" -ForegroundColor Red; exit 1 }

Write-Host "Instancias en servicio: $ids" -ForegroundColor Cyan
Write-Host "Terminando $victima (simula la falla de una instancia)..." -ForegroundColor Yellow
aws autoscaling terminate-instance-in-auto-scaling-group --instance-id $victima `
    --no-should-decrement-desired-capacity --query "Activity.Description" --output text

$ok = 0; $fallas = 0
for ($i = 1; $i -le $Segundos; $i++) {
    try {
        $r = Invoke-RestMethod -Uri "$url/api/info" -TimeoutSec 5
        $ok++
        "{0}  200  {1,-21} {2}" -f (Get-Date -Format "HH:mm:ss"), $r.instance_id, $r.availability_zone | Write-Host
    } catch {
        $fallas++
        "{0}  ERROR {1}" -f (Get-Date -Format "HH:mm:ss"), $_.Exception.Message | Write-Host -ForegroundColor Red
    }
    Start-Sleep -Seconds 1
}

Write-Host "`nResultado: $ok respuestas OK, $fallas fallidas durante la falla." -ForegroundColor Green
Write-Host "Actividad del Auto Scaling Group (reemplazo automatico):" -ForegroundColor Cyan
aws autoscaling describe-scaling-activities --auto-scaling-group-name $asg --max-items 3 `
    --query "Activities[].[StartTime,StatusCode,Description]" --output table
