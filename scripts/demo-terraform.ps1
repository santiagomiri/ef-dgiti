# Demostracion de Terraform para el video (clip 2), paso a paso con Enter.
# Muestra cada comando antes de ejecutarlo; terraform apply pide escribir "yes".
# Uso (desde la raiz del repo):  .\scripts\demo-terraform.ps1

Set-Location (Join-Path (Split-Path $PSScriptRoot -Parent) "infra")

function Paso($n, $titulo, $texto, [scriptblock]$accion) {
    Write-Host ""
    Write-Host "=== PASO $n de 6: $titulo ===" -ForegroundColor Cyan
    Read-Host "Presiona Enter para ejecutar" | Out-Null
    Write-Host "PS infra> $texto" -ForegroundColor Yellow
    & $accion
}

Paso 1 "Recursos que gestiona Terraform" "terraform state list" {
    $recursos = terraform state list
    $recursos
    Write-Host "Total: $($recursos.Count) recursos" -ForegroundColor Green
}

Paso 2 "Cambio: maximo del Auto Scaling de 4 a 5" "asg_max_size = 4  ->  asg_max_size = 5  (terraform.tfvars)" {
    (Get-Content terraform.tfvars) -replace '(asg_max_size\s+=) 4', '$1 5' | Set-Content terraform.tfvars
    Select-String asg_max_size terraform.tfvars | ForEach-Object { $_.Line }
}

Paso 3 "Inicializar" "terraform init" { terraform init }
Paso 4 "Revisar el plan" "terraform plan" { terraform plan }
Paso 5 "Aplicar (escribe yes y Enter)" "terraform apply" { terraform apply }
Paso 6 "Salidas" "terraform output" { terraform output }

Write-Host ""
Write-Host "LISTO. Ahora: Chrome -> Auto Scaling (ef-dgiti-asg) -> F5 -> Max = 5" -ForegroundColor Green
