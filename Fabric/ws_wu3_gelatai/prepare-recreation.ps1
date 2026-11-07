#requires -Version 7.0
[CmdletBinding()]
param(
    [string] $TargetWorkspaceName,
    [string] $TargetWorkspaceId,
    [string] $BindingMapPath,
    [string] $OutputDirectory,
    [switch] $Apply
)

$ErrorActionPreference = 'Stop'

function Assert-RecreationTarget {
    param([string] $Name, [string] $Id, [hashtable] $Manifest)
    if (-not $Name) { throw 'An explicit NEW target workspace name is required.' }
    if ($Name -eq $Manifest.sourceWorkspace.displayName -or $Id -eq $Manifest.sourceWorkspace.id) {
        throw 'The captured source workspace is protected. No operation was performed.'
    }
    if ($Id) { $null = [guid]::Parse($Id) }
}

function Convert-RecreationText {
    param([string] $Text, [hashtable] $Bindings, [string[]] $SourceIds)
    foreach ($source in $Bindings.values.Keys) {
        if ($source -notmatch '^(?:https?|powerbi)://|^[^;]+\.fabric\.microsoft\.com(?:,1433)?$|^GelatAI_shopdb-[0-9a-f-]{36}$') {
            throw "Binding values must identify an endpoint or physical SQL catalog, not arbitrary source text: $source"
        }
        $Text = $Text.Replace($source, [string]$Bindings.values[$source])
    }
    foreach ($source in $SourceIds) {
        if (-not $Bindings.ids.ContainsKey($source) -or -not $Text.Contains($source, [StringComparison]::OrdinalIgnoreCase)) { continue }
        $replacement = [string]$Bindings.ids[$source]
        $null = [guid]::Parse($replacement)
        $escaped = [regex]::Escape($source)
        $pattern = "(?<prefix>(?:https?|abfss|powerbi)://[^\s`"']*?[/=@?]|abfss://|semanticmodelid=|DirectQuery to AS - (?:[0-9a-f-]{36}/)?)$escaped(?![0-9a-f-])"
        $Text = [regex]::Replace($Text, $pattern, { param($match) $match.Groups['prefix'].Value + $replacement })
        $pattern = "(?<prefix>annotation ONT_(?:WorkspaceId|ItemId)\s*=\s*)$escaped(?![0-9a-f-])"
        $Text = [regex]::Replace($Text, $pattern, { param($match) $match.Groups['prefix'].Value + $replacement })
        $pattern = "(?<prefix>annotation measure_[^\r\n=]+=\s*\{[^\r\n]*`"(?:w|i)`"\s*:\s*`")$escaped(?=`")"
        $Text = [regex]::Replace($Text, $pattern, { param($match) $match.Groups['prefix'].Value + $replacement })
        $pattern = "(?<prefix>`"(?:default_lakehouse|default_lakehouse_workspace_id|workspaceId|itemId|id)`"\s*:\s*`")$escaped(?=`")"
        $Text = [regex]::Replace($Text, $pattern, { param($match) $match.Groups['prefix'].Value + $replacement })
    }
    return $Text
}

function Convert-RecreationJson {
    param($Value, [hashtable] $Bindings, [string[]] $SourceIds)
    if ($Value -is [System.Collections.IDictionary]) {
        $result = @{}
        foreach ($key in $Value.Keys) {
            $result[$key] = Convert-RecreationJson $Value[$key] $Bindings $SourceIds
        }
        return $result
    }
    if ($Value -is [array]) {
        return ,@($Value | ForEach-Object { Convert-RecreationJson $_ $Bindings $SourceIds })
    }
    if ($Value -is [string]) {
        if ($SourceIds -contains $Value -and $Bindings.ids.ContainsKey($Value)) {
            $null = [guid]::Parse([string]$Bindings.ids[$Value])
            return [string]$Bindings.ids[$Value]
        }
        if ($Value.TrimStart() -match '^[\[{]') {
            $parsed = $Value | ConvertFrom-Json -AsHashtable -Depth 100 -ErrorAction Stop
            return ConvertTo-Json -InputObject (Convert-RecreationJson $parsed $Bindings $SourceIds) -Depth 100 -Compress
        }
        return Convert-RecreationText $Value $Bindings $SourceIds
    }
    return $Value
}

if ($MyInvocation.InvocationName -eq '.') { return }
if ($Apply) {
    throw 'Deployment is blocked: the V2 ontology definition and required service configuration are not fully captured. This command prepares local payloads only; it never calls Fabric.'
}
$manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'workspace-manifest.json') -Raw |
    ConvertFrom-Json -AsHashtable -Depth 100
Assert-RecreationTarget $TargetWorkspaceName $TargetWorkspaceId $manifest
$sourceIds = @($manifest.sourceWorkspace.id) + @($manifest.items.sourceId) + @($manifest.folders.id)
$bindings = @{ ids = @{}; values = @{} }
if ($BindingMapPath) {
    $bindings = Get-Content -LiteralPath $BindingMapPath -Raw | ConvertFrom-Json -AsHashtable -Depth 100
    if ($bindings.ids -isnot [hashtable] -or $bindings.values -isnot [hashtable]) {
        throw 'Binding map must contain ids and values JSON objects.'
    }
}
if ($TargetWorkspaceId) { $bindings.ids[$manifest.sourceWorkspace.id] = $TargetWorkspaceId }
if ($OutputDirectory -and (-not $TargetWorkspaceId -or -not $BindingMapPath)) {
    throw 'Writing payloads requires TargetWorkspaceId and BindingMapPath with all target IDs/endpoints.'
}
if ($OutputDirectory) {
    $destination = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\') + '\'
    $repository = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\') + '\'
    if ($destination.StartsWith($repository, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Write prepared payloads outside the captured workspace package.'
    }
}
$order = @('Eventhouse', 'Lakehouse', 'SQLDatabase', 'KQLDatabase', 'Notebook', 'SemanticModel', 'Report', 'KQLDashboard', 'Eventstream', 'DataAgent', 'Reflex', 'Ontology')
$items = @($manifest.items | Sort-Object { $order.IndexOf($_.type) }, displayName)
$actions = @(@{ phase = 'create-folders'; folders = $manifest.folders })
$actions += @($items | Where-Object recreation -in @('definition', 'sql-schema') | ForEach-Object {
    @{ phase = 'create-item-shell'; sourceId = $_.sourceId; type = $_.type; displayName = $_.displayName; folderId = $_.folderId }
})
$actions += @{ phase = 'initialize-empty-schemas'; sources = $manifest.schemaSources; seedData = $false }
$payloads = @{}
$configurations = @()
foreach ($item in $items) {
    if ($item.recreation -in @('generated', 'parent-managed', 'blocked')) {
        $actions += @{ phase = $item.recreation; displayName = $item.displayName; sourceId = $item.sourceId; owner = $item.owner }
        continue
    }
    $actions += @{ phase = 'configure-definition'; sourceId = $item.sourceId; parts = @($item.parts.path | Where-Object { $_ -notin @('.platform', '.schedules') }) }
    if ($OutputDirectory -and $item.parts) {
        Write-Verbose "Preparing local payload: $($item.folder)"
        $parts = foreach ($part in $item.parts) {
            if ($part.path -in @('.platform', '.schedules')) { continue }
            $file = Join-Path (Join-Path $PSScriptRoot $item.folder) $part.path
            $text = [IO.File]::ReadAllText($file)
            if ($part.path -match '\.(json|pbir|pbism)$') {
                $value = $text | ConvertFrom-Json -AsHashtable -Depth 100
                if ($part.path -eq 'definition.pbir') {
                    $modelName = $item.displayName.Replace('rp_', 'sm_')
                    $model = @($manifest.items | Where-Object { $_.type -eq 'SemanticModel' -and $_.displayName -eq $modelName })
                    if ($model.Count -ne 1 -or -not $bindings.ids.ContainsKey($model[0].sourceId)) {
                        throw "A mapped semantic model is required for '$($item.displayName)'."
                    }
                    $value.datasetReference = @{ byConnection = @{ connectionString = "Data Source=powerbi://api.powerbi.com/v1.0/myorg/$TargetWorkspaceName;initial catalog=$modelName;integrated security=ClaimsToken;semanticmodelid=$($bindings.ids[$model[0].sourceId])" } }
                }
                $text = ConvertTo-Json -InputObject (Convert-RecreationJson $value $bindings $sourceIds) -Depth 100
            } else {
                $text = Convert-RecreationText $text $bindings $sourceIds
            }
            foreach ($id in $sourceIds) {
                if ($text.Contains($id, [StringComparison]::OrdinalIgnoreCase)) {
                    throw "Unresolved source reference in '$($item.folder)/$($part.path)': $id"
                }
            }
            if ($text.Contains('WORKSPACE_NAME_PLACEHOLDER')) {
                throw "Unresolved legacy semantic model endpoint in '$($item.folder)/$($part.path)'; provide its exact powerbi URI value mapping."
            }
            foreach ($property in @($manifest.items.sourceProperties | Where-Object { $_ -is [System.Collections.IDictionary] })) {
                foreach ($key in @('queryServiceUri', 'ingestionServiceUri', 'databaseName', 'serverFqdn')) {
                    if ($property[$key] -and $text.Contains([string]$property[$key])) {
                        throw "Unresolved source endpoint/catalog in '$($item.folder)/$($part.path)': $key"
                    }
                }
            }
            @{ path = $part.path; payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($text)); payloadType = 'InlineBase64' }
        }
        $payloads[$item.folder] = @{ displayName = $item.displayName; type = $item.type; definition = @{ parts = @($parts) } }
    }
    if ($item.shortcuts) { $configurations += @{ phase = 'configure-shortcuts'; sourceId = $item.sourceId; shortcuts = $item.shortcuts } }
    if ($item.connections) { $configurations += @{ phase = 'configure-connections'; sourceId = $item.sourceId; connections = $item.connections } }
    if ($item.type -eq 'Notebook') { $configurations += @{ phase = 'configure-schedules'; sourceId = $item.sourceId; schedules = @($item.schedules) } }
}
$actions += $configurations
$actions += @{ phase = 'configure-workspace-roles'; assignments = $manifest.workspaceRoleAssignments }
$plan = @{ ready = $false; targetWorkspaceName = $TargetWorkspaceName; targetWorkspaceId = $TargetWorkspaceId; blockers = $manifest.blockers; actions = $actions; networkCalls = 0 }
if ($OutputDirectory) {
    # Validate every payload first, then persist only complete local preparation results.
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    foreach ($name in $payloads.Keys) {
        ConvertTo-Json -InputObject $payloads[$name] -Depth 100 | Set-Content -LiteralPath (Join-Path $destination "$name.json") -Encoding utf8
    }
    ConvertTo-Json -InputObject $plan -Depth 100 | Set-Content -LiteralPath (Join-Path $destination 'recreation-plan.json') -Encoding utf8
}
ConvertTo-Json -InputObject $plan -Depth 100
