# Copia al portapapeles, uno por uno, los 3 valores que van en los secretos de
# GitHub, SIN mostrarlos en pantalla (seguro aunque estes grabando).
# Requiere haber guardado antes las credenciales con .\scripts\credenciales.ps1
# En GitHub: Settings > Secrets and variables > Actions > New repository secret

$archivo = Join-Path $HOME ".aws\credentials"
$valores = @{}
foreach ($linea in Get-Content $archivo) {
    if ($linea -match "^\s*(aws_access_key_id|aws_secret_access_key|aws_session_token)\s*=\s*(.+)$") {
        $valores[$Matches[1]] = $Matches[2].Trim()
    }
}

$secretos = [ordered]@{
    "AWS_ACCESS_KEY_ID"     = "aws_access_key_id"
    "AWS_SECRET_ACCESS_KEY" = "aws_secret_access_key"
    "AWS_SESSION_TOKEN"     = "aws_session_token"
}

foreach ($nombre in $secretos.Keys) {
    $valor = $valores[$secretos[$nombre]]
    if (-not $valor) { Write-Host "No se encontro $nombre en $archivo" -ForegroundColor Red; exit 1 }
    Set-Clipboard -Value $valor
    Write-Host "Copiado el valor de $nombre. Crea/actualiza el secreto '$nombre' en GitHub, pega (Ctrl+V) y guarda." -ForegroundColor Yellow
    Read-Host "Presiona Enter para continuar" | Out-Null
}
Set-Clipboard -Value " "
Write-Host "Listo. Portapapeles limpio." -ForegroundColor Green
