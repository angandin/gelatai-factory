[CmdletBinding()]
param(
    [string] $WorkspaceName = 'ws_wu3_gelatai',
    [string] $DatabaseName = 'GelatAI_shopdb',
    [string] $Collation = 'SQL_Latin1_General_CP1_CI_AS',
    [ValidateRange(1, 35)]
    [int] $BackupRetentionDays = 7,
    [switch] $SalesOnly
)

$ErrorActionPreference = 'Stop'
$fabricResource = 'https://api.fabric.microsoft.com'
$fabricApi = "$fabricResource/v1"
$skillName = 'sqldb-cli'
$sqlScriptPaths = if ($SalesOnly) {
    @(Join-Path $PSScriptRoot 'sales-schema.sql')
} else { @(
    (Join-Path $PSScriptRoot 'schema.sql')
    (Join-Path $PSScriptRoot 'seed-apishop.sql')
    (Join-Path $PSScriptRoot 'sales-schema.sql')
) }

function Invoke-FabricRest {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('GET', 'POST')]
        [string] $Method,
        [Parameter(Mandatory)]
        [string] $Url,
        [object] $Body
    )

    $token = az account get-access-token `
        --resource $fabricResource `
        --query accessToken `
        --output tsv
    if (-not $token) {
        throw 'Could not acquire a Microsoft Fabric access token. Run az login and retry.'
    }

    $headers = @{
        Authorization = "Bearer $token"
        'x-ms-fabric-skill' = $skillName
    }
    $parameters = @{
        Method = $Method
        Uri = $Url
        Headers = $headers
        UseBasicParsing = $true
    }
    if ($null -ne $Body) {
        $parameters.ContentType = 'application/json'
        $parameters.Body = $Body | ConvertTo-Json -Depth 10
    }

    Invoke-WebRequest @parameters
}

function Get-FabricCollection {
    param(
        [Parameter(Mandatory)]
        [string] $Url
    )

    $items = @()
    $nextUrl = $Url
    while ($nextUrl) {
        $response = Invoke-FabricRest -Method GET -Url $nextUrl
        $content = $response.Content | ConvertFrom-Json
        $items += @($content.value)
        $nextUrl = $content.continuationUri
    }

    $items
}

function Wait-FabricOperation {
    param(
        [Parameter(Mandatory)]
        [string] $OperationUrl,
        [int] $RetryAfterSeconds = 5
    )

    do {
        Start-Sleep -Seconds $RetryAfterSeconds
        $response = Invoke-FabricRest -Method GET -Url $OperationUrl
        $operation = $response.Content | ConvertFrom-Json
        Write-Host "Fabric operation status: $($operation.status)"
        if ($operation.status -eq 'Failed') {
            throw "Fabric operation failed: $($response.Content)"
        }
    } while ($operation.status -notin @('Succeeded', 'Completed'))
}

foreach ($sqlScriptPath in $sqlScriptPaths) {
    if (-not (Test-Path $sqlScriptPath -PathType Leaf)) {
        throw "SQL deployment script not found: $sqlScriptPath"
    }
}

$null = Get-Command az -ErrorAction Stop
$sqlcmdCandidates = @(
    (Join-Path $env:ProgramW6432 'SqlCmd\sqlcmd.exe')
    (Join-Path $env:ProgramFiles 'SqlCmd\sqlcmd.exe')
    (Get-Command sqlcmd -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source)
) | Where-Object { $_ -and (Test-Path $_ -PathType Leaf) } | Select-Object -Unique
$sqlcmdPath = $null
foreach ($candidate in $sqlcmdCandidates) {
    $version = & $candidate --version 2>$null
    if ($LASTEXITCODE -eq 0 -and $version) {
        $sqlcmdPath = $candidate
        break
    }
}
if (-not $sqlcmdPath) {
    throw 'The Go sqlcmd CLI is required. Install it with: winget install Microsoft.Sqlcmd'
}

$workspaces = Get-FabricCollection -Url "$fabricApi/workspaces"
$workspaceMatches = @($workspaces | Where-Object displayName -eq $WorkspaceName)
if ($workspaceMatches.Count -ne 1) {
    throw "Expected exactly one workspace named '$WorkspaceName'; found $($workspaceMatches.Count)."
}

$workspace = (Invoke-FabricRest -Method GET -Url "$fabricApi/workspaces/$($workspaceMatches[0].id)").Content |
    ConvertFrom-Json
if (-not $workspace.capacityId) {
    throw "Workspace '$WorkspaceName' is not assigned to a Fabric capacity."
}

$databaseItemsUrl = "$fabricApi/workspaces/$($workspace.id)/items?type=SQLDatabase"
$databaseMatches = @(
    Get-FabricCollection -Url $databaseItemsUrl |
        Where-Object displayName -eq $DatabaseName
)
if ($databaseMatches.Count -gt 1) {
    throw "More than one SQL database named '$DatabaseName' exists in workspace '$WorkspaceName'."
}

if ($databaseMatches.Count -eq 0) {
    if ($SalesOnly) {
        throw "Sales-only deployment requires the existing SQL database '$DatabaseName'."
    }
    Write-Host "Creating Fabric SQL Database '$DatabaseName'..."
    $createResponse = Invoke-FabricRest -Method POST -Url "$fabricApi/workspaces/$($workspace.id)/items" -Body @{
        displayName = $DatabaseName
        type = 'SQLDatabase'
        description = 'Operational data for GelatAI shops, employees, products, inventory, shipments, and sales.'
        creationPayload = @{
            creationMode = 'new'
            collation = $Collation
            backupRetentionDays = $BackupRetentionDays
        }
    }

    if ($createResponse.StatusCode -eq 202) {
        $operationUrl = @($createResponse.Headers.Location)[0]
        if (-not $operationUrl) {
            throw 'Fabric accepted database creation but did not return an operation URL.'
        }
        $retryAfter = if ($createResponse.Headers.'Retry-After') {
            [int] @($createResponse.Headers.'Retry-After')[0]
        } else {
            5
        }
        Wait-FabricOperation -OperationUrl $operationUrl -RetryAfterSeconds $retryAfter
    } elseif ($createResponse.StatusCode -notin @(200, 201)) {
        throw "Unexpected Fabric create response: HTTP $($createResponse.StatusCode)."
    }

    $databaseMatches = @(
        Get-FabricCollection -Url $databaseItemsUrl |
            Where-Object displayName -eq $DatabaseName
    )
    if ($databaseMatches.Count -ne 1) {
        throw "Database '$DatabaseName' was not found after the create operation completed."
    }
} else {
    Write-Host "Using existing Fabric SQL Database '$DatabaseName'."
}

$databaseId = $databaseMatches[0].id
$databaseDetailsUrl = "$fabricApi/workspaces/$($workspace.id)/sqlDatabases/$databaseId"
$provisioningDeadline = (Get-Date).AddMinutes(20)
do {
    $database = (Invoke-FabricRest -Method GET -Url $databaseDetailsUrl).Content | ConvertFrom-Json
    if ($database.properties.serverFqdn -and $database.properties.databaseName) {
        break
    }
    if ((Get-Date) -ge $provisioningDeadline) {
        throw "Timed out waiting for SQL endpoint provisioning for '$DatabaseName'."
    }
    Start-Sleep -Seconds 10
} while ($true)

foreach ($sqlScriptPath in $sqlScriptPaths) {
    Write-Host "Applying '$([System.IO.Path]::GetFileName($sqlScriptPath))' to '$($database.properties.databaseName)'..."
    & $sqlcmdPath `
            -S $database.properties.serverFqdn `
            -d $database.properties.databaseName `
            -G `
            -b `
            -i $sqlScriptPath
    if ($LASTEXITCODE -ne 0) {
        throw "Deployment of '$sqlScriptPath' failed with sqlcmd exit code $LASTEXITCODE."
    }
}

Write-Host "Deployment complete. Workspace: $WorkspaceName; Database: $DatabaseName; Item ID: $databaseId"
