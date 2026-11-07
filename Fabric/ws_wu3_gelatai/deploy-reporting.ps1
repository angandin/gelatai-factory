[CmdletBinding()]
param(
    [string] $WorkspaceName = 'ws_wu3_gelatai',
    [string] $SqlDatabaseName = 'GelatAI_shopdb',
    [string] $LakehouseName = 'GelatAI_lakehouse',
    [string] $SemanticModelName = 'sm_gelatai_lh',
    [string] $ReportName = 'rp_gelatai_lh'
)

$ErrorActionPreference = 'Stop'
$fabricResource = 'https://api.fabric.microsoft.com'
$fabricApi = "$fabricResource/v1"
$workspaceRoot = $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $workspaceRoot 'workspace-manifest.json') -Raw | ConvertFrom-Json
$semanticModelRoot = Join-Path $workspaceRoot "$SemanticModelName.SemanticModel"
$reportRoot = Join-Path $workspaceRoot "$ReportName.Report"

function Invoke-FabricRest {
    param(
        [Parameter(Mandatory)][ValidateSet('GET', 'POST')][string] $Method,
        [Parameter(Mandatory)][string] $Url,
        [Parameter(Mandatory)][string] $Skill,
        [object] $Body
    )

    $token = az account get-access-token `
        --resource $fabricResource `
        --query accessToken `
        --output tsv
    if (-not $token) {
        throw 'Could not acquire a Microsoft Fabric access token. Run az login and retry.'
    }

    $parameters = @{
        Method = $Method
        Uri = $Url
        Headers = @{
            Authorization = "Bearer $token"
            'x-ms-fabric-skill' = $Skill
        }
        UseBasicParsing = $true
    }
    if ($null -ne $Body) {
        $parameters.ContentType = 'application/json'
        $parameters.Body = $Body | ConvertTo-Json -Depth 100
    }

    Invoke-WebRequest @parameters
}

function Get-FabricCollection {
    param(
        [Parameter(Mandatory)][string] $Url,
        [Parameter(Mandatory)][string] $Skill
    )

    $items = @()
    $nextUrl = $Url
    while ($nextUrl) {
        $response = Invoke-FabricRest -Method GET -Url $nextUrl -Skill $Skill
        $content = $response.Content | ConvertFrom-Json
        $items += @($content.value)
        $nextUrl = $content.continuationUri
    }
    $items
}

function Wait-FabricOperation {
    param(
        [Parameter(Mandatory)][string] $OperationUrl,
        [Parameter(Mandatory)][string] $Skill,
        [int] $RetryAfterSeconds = 5
    )

    do {
        Start-Sleep -Seconds $RetryAfterSeconds
        $response = Invoke-FabricRest -Method GET -Url $OperationUrl -Skill $Skill
        $operation = $response.Content | ConvertFrom-Json
        Write-Host "Fabric operation status: $($operation.status)"
        if ($operation.status -eq 'Failed') {
            throw "Fabric operation failed: $($response.Content)"
        }
    } while ($operation.status -notin @('Succeeded', 'Completed'))
}

function ConvertTo-DefinitionParts {
    param(
        [Parameter(Mandatory)][string] $Root,
        [Parameter(Mandatory)][scriptblock] $ContentTransform,
        [string[]] $ExcludedExtensions = @()
    )

    $item = @($manifest.items | Where-Object folder -eq (Split-Path $Root -Leaf))
    if ($item.Count -ne 1 -or -not $item[0].parts) {
        throw "No captured definition part list exists for '$Root'."
    }
    $item[0].parts |
        Where-Object path -ne '.platform' |
        ForEach-Object { Get-Item -LiteralPath (Join-Path $Root $_.path) } |
        Where-Object {
            $_.Name -ne '.platform' -and
            $_.Extension -notin $ExcludedExtensions
        } |
        ForEach-Object {
            $relativePath = $_.FullName.Substring($Root.Length + 1).Replace('\', '/')
            $content = [IO.File]::ReadAllBytes($_.FullName)
            $transformed = & $ContentTransform $relativePath $content
            @{
                path = $relativePath
                payload = [Convert]::ToBase64String($transformed)
                payloadType = 'InlineBase64'
            }
        }
}

function Invoke-DefinitionUpsert {
    param(
        [Parameter(Mandatory)][string] $WorkspaceId,
        [Parameter(Mandatory)][string] $DisplayName,
        [Parameter(Mandatory)][ValidateSet('SemanticModel', 'Report')][string] $Type,
        [Parameter(Mandatory)][array] $Parts,
        [Parameter(Mandatory)][string] $Skill
    )

    $itemsUrl = "$fabricApi/workspaces/$WorkspaceId/items?type=$Type"
    $matches = @(
        Get-FabricCollection -Url $itemsUrl -Skill $Skill |
            Where-Object displayName -eq $DisplayName
    )
    if ($matches.Count -gt 1) {
        throw "More than one $Type named '$DisplayName' exists in workspace '$WorkspaceName'."
    }

    $body = @{
        displayName = $DisplayName
        type = $Type
        definition = @{ parts = @($Parts) }
    }

    if ($matches.Count -eq 0) {
        Write-Host "Creating $Type '$DisplayName'..."
        $response = Invoke-FabricRest `
            -Method POST `
            -Url "$fabricApi/workspaces/$WorkspaceId/items" `
            -Skill $Skill `
            -Body $body
    } else {
        Write-Host "Updating $Type '$DisplayName'..."
        $itemId = $matches[0].id
        $response = Invoke-FabricRest `
            -Method POST `
            -Url "$fabricApi/workspaces/$WorkspaceId/items/$itemId/updateDefinition" `
            -Skill $Skill `
            -Body @{ definition = $body.definition }
    }

    if ($response.StatusCode -eq 202) {
        $operationUrl = @($response.Headers.Location)[0]
        if (-not $operationUrl) {
            throw "Fabric accepted the $Type operation but did not return an operation URL."
        }
        $retryAfter = if ($response.Headers.'Retry-After') {
            [int] @($response.Headers.'Retry-After')[0]
        } else {
            5
        }
        Wait-FabricOperation -OperationUrl $operationUrl -Skill $Skill -RetryAfterSeconds $retryAfter
    } elseif ($response.StatusCode -notin @(200, 201)) {
        throw "Unexpected $Type response: HTTP $($response.StatusCode)."
    }

    $resolved = @(
        Get-FabricCollection -Url $itemsUrl -Skill $Skill |
            Where-Object displayName -eq $DisplayName
    )
    if ($resolved.Count -ne 1) {
        throw "Expected exactly one $Type named '$DisplayName' after deployment."
    }
    $resolved[0]
}

foreach ($requiredPath in @($semanticModelRoot, $reportRoot)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Container)) {
        throw "Reporting definition folder not found: $requiredPath"
    }
}

$null = Get-Command az -ErrorAction Stop
$workspaces = Get-FabricCollection -Url "$fabricApi/workspaces" -Skill 'semantic-model-authoring'
$workspaceMatches = @($workspaces | Where-Object displayName -eq $WorkspaceName)
if ($workspaceMatches.Count -ne 1) {
    throw "Expected exactly one workspace named '$WorkspaceName'; found $($workspaceMatches.Count)."
}
$workspace = (
    Invoke-FabricRest `
        -Method GET `
        -Url "$fabricApi/workspaces/$($workspaceMatches[0].id)" `
        -Skill 'semantic-model-authoring'
).Content | ConvertFrom-Json
if (-not $workspace.capacityId) {
    throw "Workspace '$WorkspaceName' is not assigned to a Fabric capacity."
}

$sqlDatabaseMatches = @(
    Get-FabricCollection `
        -Url "$fabricApi/workspaces/$($workspace.id)/items?type=SQLDatabase" `
        -Skill 'semantic-model-authoring' |
        Where-Object displayName -eq $SqlDatabaseName
)
if ($sqlDatabaseMatches.Count -ne 1) {
    throw "Expected exactly one SQL Database named '$SqlDatabaseName'; found $($sqlDatabaseMatches.Count)."
}
$sqlDatabase = (
    Invoke-FabricRest `
        -Method GET `
        -Url "$fabricApi/workspaces/$($workspace.id)/sqlDatabases/$($sqlDatabaseMatches[0].id)" `
        -Skill 'semantic-model-authoring'
).Content | ConvertFrom-Json

$lakehouseMatches = @(
    Get-FabricCollection `
        -Url "$fabricApi/workspaces/$($workspace.id)/items?type=Lakehouse" `
        -Skill 'semantic-model-authoring' |
        Where-Object displayName -eq $LakehouseName
)
if ($lakehouseMatches.Count -ne 1) {
    throw "Expected exactly one Lakehouse named '$LakehouseName'; found $($lakehouseMatches.Count)."
}
$lakehouse = $lakehouseMatches[0]

$semanticParts = ConvertTo-DefinitionParts -Root $semanticModelRoot -ContentTransform {
    param($RelativePath, $Content)
    if ($RelativePath -notlike '*.tmdl') {
        return $Content
    }

    $text = [Text.Encoding]::UTF8.GetString($Content)
    if ($RelativePath -eq 'definition/expressions.tmdl') {
        $currentExpression = $null
        $lines = $text -split "`r?`n"
        $lines = foreach ($line in $lines) {
            if ($line -match "^expression '([^']+)' =") {
                $currentExpression = $Matches[1]
            }
            if ($line -match 'AzureStorage\.DataLake\("https://onelake\.dfs\.fabric\.microsoft\.com/') {
                $sourceItemId = switch ($currentExpression) {
                    'DirectLake - GelatAI_lakehouse' { $lakehouse.id }
                    'DirectLake - GelatAI_shopdb' { $sqlDatabaseMatches[0].id }
                    default { $null }
                }
                if ($sourceItemId) {
                    $line = [regex]::Replace(
                        $line,
                        'https://onelake\.dfs\.fabric\.microsoft\.com/[0-9a-f-]+/[0-9a-f-]+',
                        "https://onelake.dfs.fabric.microsoft.com/$($workspace.id)/$sourceItemId"
                    )
                }
            }
            $line
        }
        $text = $lines -join [Environment]::NewLine
    }
    [Text.Encoding]::UTF8.GetBytes($text)
}

$semanticModel = Invoke-DefinitionUpsert `
    -WorkspaceId $workspace.id `
    -DisplayName $SemanticModelName `
    -Type SemanticModel `
    -Parts $semanticParts `
    -Skill 'semantic-model-authoring'

$validator = Get-Command powerbi-report-author -ErrorAction SilentlyContinue
if ($validator) {
    & $validator.Source validate $reportRoot --pretty
    if ($LASTEXITCODE -ne 0) {
        throw 'PBIR validation failed. The report was not deployed.'
    }
}

$reportParts = ConvertTo-DefinitionParts `
    -Root $reportRoot `
    -ExcludedExtensions @('.ps1') `
    -ContentTransform {
        param($RelativePath, $Content)
        if ($RelativePath -ne 'definition.pbir') {
            return $Content
        }

        $definition = [Text.Encoding]::UTF8.GetString($Content) | ConvertFrom-Json
        $definition.datasetReference = @{ byConnection = @{ connectionString =
            "Data Source=powerbi://api.powerbi.com/v1.0/myorg/$WorkspaceName;" +
            "initial catalog=$SemanticModelName;" +
            'integrated security=ClaimsToken;' +
            "semanticmodelid=$($semanticModel.id)"
        } }
        [Text.Encoding]::UTF8.GetBytes(($definition | ConvertTo-Json -Depth 20))
    }

$report = Invoke-DefinitionUpsert `
    -WorkspaceId $workspace.id `
    -DisplayName $ReportName `
    -Type Report `
    -Parts $reportParts `
    -Skill 'powerbi-report-authoring'

Write-Host "Reporting deployment complete. Semantic model ID: $($semanticModel.id); Report ID: $($report.id)"
