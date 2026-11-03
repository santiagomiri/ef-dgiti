# Copia al portapapeles los valores que van en los secretos de GitHub, SIN
# mostrarlos en pantalla (seguro aunque estes grabando).
# Requiere haber guardado antes las credenciales con .\scripts\credenciales.ps1
# En GitHub: Settings > Secrets and variables > Actions > New repository secret
#
# Uso:  .\scripts\copiar-secretos.ps1                          (los 3, uno por uno con Enter)
#       .\scripts\copiar-secretos.ps1 -Solo AWS_SESSION_TOKEN   (copia solo ese y termina)
param(
    [ValidateSet("", "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN")]
    [string]$Solo = ""
)

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
$nombres = if ($Solo) { @($Solo) } else { @($secretos.Keys) }

foreach ($nombre in $nombres) {
    $valor = $valores[$secretos[$nombre]]
    if (-not $valor) { Write-Host "No se encontro $nombre en $archivo" -ForegroundColor Red; exit 1 }
    Set-Clipboard -Value $valor
    Write-Host "Copiado el valor de $nombre ($($valor.Length) caracteres). En GitHub: pega con Ctrl+V en 'Secret' y guarda." -ForegroundColor Yellow
    if (-not $Solo) { Read-Host "Presiona Enter para continuar" | Out-Null }
}
if (-not $Solo) {
    Set-Clipboard -Value " "
    Write-Host "Listo. Portapapeles limpio." -ForegroundColor Green
}
