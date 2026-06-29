param(
    [Parameter(Mandatory=$true)][string]$ContentJson,
    [Parameter(Mandatory=$true)][string]$OutDir
)

$json = Get-Content -Raw -Path $ContentJson | ConvertFrom-Json
$parts = $json.definition.parts
if (-not $parts) { Write-Error "No definition.parts in $ContentJson"; exit 1 }

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
foreach ($p in $parts) {
    $target = Join-Path $OutDir $p.path
    $dir = Split-Path $target -Parent
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $bytes = [System.Convert]::FromBase64String($p.payload)
    [System.IO.File]::WriteAllBytes($target, $bytes)
    Write-Host "  wrote $($p.path)"
}
Write-Host "Done: $OutDir"
