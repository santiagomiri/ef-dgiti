# Guarda las credenciales del Sandbox de AWS Academy en ~/.aws/credentials.
# 1. Ejecuta este script y NO toques la ventana.
# 2. En AWS Academy: AWS Details > AWS CLI: Show > selecciona el bloque [default] > clic derecho > Copiar.
# El script detecta el portapapeles, guarda el archivo y muestra tu identidad.

$dir = Join-Path $HOME ".aws"
if (-not (Test-Path $dir)) { New-Item -ItemType Directory $dir | Out-Null }

Write-Host "Copia ahora el bloque [default] desde AWS Details. NO toques esta ventana." -ForegroundColor Yellow
do {
    Start-Sleep -Milliseconds 700
    $c = Get-Clipboard -Raw
} until ($c -and $c.TrimStart().StartsWith("[default]"))

Set-Content -Encoding ascii -Path (Join-Path $dir "credentials") -Value $c
Set-Clipboard -Value " "   # limpia el portapapeles
Write-Host "Credenciales guardadas." -ForegroundColor Green
aws sts get-caller-identity --query "Arn" --output text
