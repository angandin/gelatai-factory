param(
    [Parameter(Mandatory=$true)][string]$ContentJson,
    [Parameter(Mandatory=$true)][string]$OutDir
)

$ErrorActionPreference = 'Stop'
$json = Get-Content -Raw -LiteralPath $ContentJson | ConvertFrom-Json
$parts = $json.definition.parts
if (-not $parts) { Write-Error "No definition.parts in $ContentJson"; exit 1 }

$root = [IO.Path]::GetFullPath($OutDir).TrimEnd('\') + '\'
$targets = @{}
$decoded = foreach ($p in $parts) {
    if ($p.payloadType -ne 'InlineBase64') {
        throw "Unsupported payload type '$($p.payloadType)' for '$($p.path)'."
    }
    $target = [IO.Path]::GetFullPath((Join-Path $root $p.path))
    if (-not $target.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Definition part escapes the output directory: $($p.path)"
    }
    if ($targets.ContainsKey($target)) {
        throw "Duplicate definition part: $($p.path)"
    }
    $targets[$target] = $true
    @{ target = $target; path = $p.path; bytes = [Convert]::FromBase64String($p.payload) }
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
foreach ($p in $decoded) {
    $target = $p.target
    $dir = Split-Path $target -Parent
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    [System.IO.File]::WriteAllBytes($target, $p.bytes)
    Write-Host "  wrote $($p.path)"
}
Write-Host "Done: $OutDir"
