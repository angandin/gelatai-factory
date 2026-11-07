#requires -Version 7.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'prepare-recreation.ps1')
$manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'workspace-manifest.json') -Raw | ConvertFrom-Json -AsHashtable -Depth 100
$count = 0
function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
    $script:count++
}
function Assert-Throws([scriptblock] $Action, [string] $Pattern) {
    $failure = $null
    try { & $Action | Out-Null } catch { $failure = $_ }
    Assert-True ($null -ne $failure -and $failure.Exception.Message -match $Pattern) "Expected failure matching '$Pattern'; received '$failure'."
}

$scripts = @((Join-Path (Split-Path $PSScriptRoot -Parent) 'export-part-writer.ps1')) +
    @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -Recurse | Select-Object -ExpandProperty FullName)
foreach ($file in $scripts) {
    $tokens = $null; $errors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$errors)
    Assert-True (-not $errors) "Parser errors in $file`: $errors"
}
Assert-Throws { Assert-RecreationTarget 'ws_wu3_gelatai' '' $manifest } 'protected'
Assert-Throws { Assert-RecreationTarget 'new-target' $manifest.sourceWorkspace.id $manifest } 'protected'
Assert-Throws { & (Join-Path $PSScriptRoot 'prepare-recreation.ps1') -TargetWorkspaceName 'new-target' -Apply } 'Deployment is blocked'
$plan = & (Join-Path $PSScriptRoot 'prepare-recreation.ps1') -TargetWorkspaceName 'offline-target' | ConvertFrom-Json
Assert-True ($plan.networkCalls -eq 0 -and -not $plan.ready -and $plan.blockers.Count -ge 2) 'Offline plan did not preserve no-write blockers.'
$phases = @($plan.actions.phase)
$lastDefinition = [Array]::LastIndexOf($phases, 'configure-definition')
Assert-True ([Array]::IndexOf($phases, 'configure-shortcuts') -gt $lastDefinition) 'Shortcuts must follow definition/schema preparation.'
Assert-True (-not ($plan.actions | Where-Object { $_.phase -eq 'create-item-shell' -and $_.sourceId -in @($manifest.items | Where-Object recreation -in @('generated', 'parent-managed') | ForEach-Object sourceId) })) 'Generated resources must never be independently created.'

$source = $manifest.sourceWorkspace.id
$item = ($manifest.items | Where-Object type -eq Lakehouse).sourceId
$target = '11111111-1111-4111-8111-111111111111'
$targetItem = '22222222-2222-4222-8222-222222222222'
$bindings = @{ ids = @{ $source = $target; $item = $targetItem }; values = @{} }
$uri = "abfss://$source@onelake.dfs.fabric.microsoft.com/$item/Tables"
Assert-True ((Convert-RecreationText $uri $bindings @($source, $item)) -eq "abfss://$target@onelake.dfs.fabric.microsoft.com/$targetItem/Tables") 'ABFSS bindings were not remapped.'
$value = @{ workspaceId = $source; lineageTag = '33333333-3333-4333-8333-333333333333'; nested = "[{`"itemId`":`"$item`"}]" }
$mapped = Convert-RecreationJson $value $bindings @($source, $item)
Assert-True ($mapped.workspaceId -eq $target -and $mapped.lineageTag -eq $value.lineageTag -and ($mapped.nested | ConvertFrom-Json)[0].itemId -eq $targetItem) 'Structured remapping changed lineage or missed nested item references.'
$ontology = "DirectQuery to AS - $source/$item`nannotation ONT_WorkspaceId = $source`nannotation measure_Test = {`"w`":`"$source`",`"i`":`"$item`"}`nannotation ONT_SemanticModelServer = powerbi://api.powerbi.com/v1.0/$source"
$mappedOntology = Convert-RecreationText $ontology $bindings @($source, $item)
Assert-True (-not $mappedOntology.Contains($source) -and -not $mappedOntology.Contains($item) -and $mappedOntology.Contains("DirectQuery to AS - $target/$targetItem")) 'Ontology model aliases/annotations were not field-aware remapped.'
Assert-Throws { & (Join-Path $PSScriptRoot 'rp_gelatai_lh.Report\author-logistics-pages.ps1') } 'OverwriteCapturedBaseline'

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('gelatai-offline-tests-' + [guid]::NewGuid())
$null = New-Item -ItemType Directory -Path $scratch
try {
    $writer = Join-Path (Split-Path $PSScriptRoot -Parent) 'export-part-writer.ps1'
    $inputFile = Join-Path $scratch 'definition.json'
    $output = Join-Path $scratch 'decoded'
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('valid'))
    foreach ($case in @(
        @{ name = 'traversal'; paths = @('safe.json', '..\escape.json'); payload = $encoded; pattern = 'escapes' },
        @{ name = 'duplicate'; paths = @('same.json', 'same.json'); payload = $encoded; pattern = 'Duplicate' },
        @{ name = 'base64'; paths = @('safe.json'); payload = '!invalid!'; pattern = 'Base-64' }
    )) {
        $parts = @($case.paths | ForEach-Object { @{ path = $_; payload = $case.payload; payloadType = 'InlineBase64' } })
        @{ definition = @{ parts = $parts } } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $inputFile
        Assert-Throws { & $writer -ContentJson $inputFile -OutDir $output } $case.pattern
        Assert-True (-not (Test-Path $output)) "Writer partially persisted the invalid $($case.name) case."
    }
    @{ definition = @{ parts = @(@{ path = 'nested\valid.json'; payload = $encoded; payloadType = 'InlineBase64' }) } } |
        ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $inputFile
    & $writer -ContentJson $inputFile -OutDir $output
    Assert-True ((Get-Content -LiteralPath (Join-Path $output 'nested\valid.json') -Raw) -eq 'valid') 'Valid export did not round trip.'

    $allBindings = @{ ids = @{}; values = @{ 'powerbi://api.powerbi.com/v1.0/myorg/WORKSPACE_NAME_PLACEHOLDER' = 'powerbi://api.powerbi.com/v1.0/myorg/offline-target' } }
    foreach ($id in (@($manifest.sourceWorkspace.id) + @($manifest.items.sourceId) + @($manifest.folders.id))) {
        $allBindings.ids[$id] = [guid]::NewGuid().ToString()
    }
    foreach ($item in $manifest.items) {
        if (-not $item.sourceProperties) { continue }
        foreach ($key in @('queryServiceUri', 'ingestionServiceUri', 'databaseName', 'serverFqdn')) {
            if (-not $item.sourceProperties[$key]) { continue }
            $allBindings.values[[string]$item.sourceProperties[$key]] = switch ($key) {
                'databaseName' { 'GelatAI_shopdb-' + [guid]::NewGuid() }
                'serverFqdn' { 'offline.database.fabric.microsoft.com,1433' }
                default { 'https://offline.kusto.fabric.microsoft.com' }
            }
        }
    }
    $mapFile = Join-Path $scratch 'bindings.json'
    ConvertTo-Json -InputObject $allBindings -Depth 100 | Set-Content -LiteralPath $mapFile
    $prepared = Join-Path $scratch 'prepared'
    $preparedPlan = & (Join-Path $PSScriptRoot 'prepare-recreation.ps1') -TargetWorkspaceName 'offline-target' `
        -TargetWorkspaceId $allBindings.ids[$manifest.sourceWorkspace.id] -BindingMapPath $mapFile -OutputDirectory $prepared |
        ConvertFrom-Json
    Assert-True (-not $preparedPlan.ready -and $preparedPlan.networkCalls -eq 0) 'Prepared payloads must remain explicitly blocked and offline.'
    Assert-True (@(Get-ChildItem -LiteralPath $prepared -Filter '*.json').Count -eq 19) 'Expected 18 independent definition payloads plus the blocked plan.'
    $factory = Get-Content -LiteralPath (Join-Path $prepared 'GelatAI-eventstream-factory.Eventstream.json') -Raw | ConvertFrom-Json
    Assert-True (-not @($factory.definition.parts | Where-Object path -in @('.platform', '.schedules')).Count) 'Metadata was incorrectly published as a definition part.'
    $eventstream = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($factory.definition.parts | Where-Object path -eq 'eventstream.json').payload)) | ConvertFrom-Json
    $sourceEventstream = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'GelatAI-eventstream-factory.Eventstream\eventstream.json') -Raw | ConvertFrom-Json
    Assert-True ($eventstream.sources[0].id -eq $sourceEventstream.sources[0].id -and $eventstream.destinations[0].properties.workspaceId -eq $allBindings.ids[$manifest.sourceWorkspace.id]) 'Remapping changed event node identity or failed to remap its destination.'
} finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force
}
Write-Output "Passed $count offline PowerShell assertions; no Fabric calls."
