[CmdletBinding()]
param(
    [string] $WorkspaceName = 'ws_wu3_gelatai',
    [string] $NotebookName = 'nb_update_shop_registry',
    [string] $ScheduleTimeUtc = '02:00',
    [ValidateSet('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday')]
    [string] $ScheduleDay = 'Monday'
)

$ErrorActionPreference = 'Stop'
$fabricResource = 'https://api.fabric.microsoft.com'
$fabricApi = "$fabricResource/v1"
$skillName = 'spark-authoring-cli'
$sourcePath = Join-Path $PSScriptRoot 'notebook-content.py'

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

    $parameters = @{
        Method = $Method
        Uri = $Url
        Headers = @{
            Authorization = "Bearer $token"
            'x-ms-fabric-skill' = $skillName
        }
        UseBasicParsing = $true
    }
    if ($null -ne $Body) {
        $parameters.ContentType = 'application/json'
        $parameters.Body = $Body | ConvertTo-Json -Depth 20
    }

    Invoke-WebRequest @parameters
}

function Get-FabricCollection {
    param([Parameter(Mandatory)][string] $Url)

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
    param([Parameter(Mandatory)][string] $OperationUrl)

    do {
        Start-Sleep -Seconds 5
        $response = Invoke-FabricRest -Method GET -Url $OperationUrl
        $operation = $response.Content | ConvertFrom-Json
        Write-Host "Fabric operation status: $($operation.status)"
        if ($operation.status -eq 'Failed') {
            throw "Fabric operation failed: $($response.Content)"
        }
    } while ($operation.status -notin @('Succeeded', 'Completed'))
}

function Wait-IfAccepted {
    param([Parameter(Mandatory)] $Response)

    if ($Response.StatusCode -eq 202) {
        $operationUrl = @($Response.Headers.Location)[0]
        if (-not $operationUrl) {
            throw 'Fabric accepted the operation but did not return an operation URL.'
        }
        Wait-FabricOperation -OperationUrl $operationUrl
    } elseif ($Response.StatusCode -notin @(200, 201)) {
        throw "Unexpected Fabric response: HTTP $($Response.StatusCode)."
    }
}

if (-not (Test-Path $sourcePath -PathType Leaf)) {
    throw "Notebook source not found: $sourcePath"
}

$null = Get-Command az -ErrorAction Stop
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

$payload = [Convert]::ToBase64String([IO.File]::ReadAllBytes($sourcePath))
$definition = @{
    definition = @{
        parts = @(
            @{
                path = 'notebook-content.py'
                payload = $payload
                payloadType = 'InlineBase64'
            }
        )
    }
}

$notebooksUrl = "$fabricApi/workspaces/$($workspace.id)/items?type=Notebook"
$notebookMatches = @(Get-FabricCollection -Url $notebooksUrl | Where-Object displayName -eq $NotebookName)
if ($notebookMatches.Count -gt 1) {
    throw "More than one notebook named '$NotebookName' exists in workspace '$WorkspaceName'."
}

if ($notebookMatches.Count -eq 0) {
    Write-Host "Creating notebook '$NotebookName'..."
    $createResponse = Invoke-FabricRest -Method POST -Url "$fabricApi/workspaces/$($workspace.id)/items" -Body @{
        displayName = $NotebookName
        type = 'Notebook'
        description = 'Creates and updates the GelatAI static shop registry once per week.'
        definition = $definition.definition
    }
    Wait-IfAccepted -Response $createResponse
    $notebookMatches = @(Get-FabricCollection -Url $notebooksUrl | Where-Object displayName -eq $NotebookName)
    if ($notebookMatches.Count -ne 1) {
        throw "Notebook '$NotebookName' was not found after creation completed."
    }
} else {
    Write-Host "Updating notebook '$NotebookName'..."
    $updateResponse = Invoke-FabricRest `
        -Method POST `
        -Url "$fabricApi/workspaces/$($workspace.id)/items/$($notebookMatches[0].id)/updateDefinition" `
        -Body $definition
    Wait-IfAccepted -Response $updateResponse
}

$notebookId = $notebookMatches[0].id
$schedulesUrl = "$fabricApi/workspaces/$($workspace.id)/items/$notebookId/jobs/RunNotebook/schedules"
$schedules = @(Get-FabricCollection -Url $schedulesUrl)
$matchingSchedule = @(
    $schedules |
        Where-Object {
            $_.configuration.type -eq 'Weekly' -and
            $_.configuration.times -contains $ScheduleTimeUtc -and
            $_.configuration.weekDays -contains $ScheduleDay
        }
)

if ($matchingSchedule.Count -eq 0) {
    Write-Host "Creating weekly schedule: $ScheduleDay at $ScheduleTimeUtc UTC..."
    $scheduleResponse = Invoke-FabricRest -Method POST -Url $schedulesUrl -Body @{
        enabled = $true
        configuration = @{
            startDateTime = '2026-10-01T00:00:00.000Z'
            endDateTime = '2036-10-01T00:00:00.000Z'
            type = 'Weekly'
            interval = 1
            localTimeZoneId = 'UTC'
            times = @($ScheduleTimeUtc)
            weekDays = @($ScheduleDay)
        }
    }
    Wait-IfAccepted -Response $scheduleResponse
} else {
    Write-Host 'Matching weekly schedule already exists.'
}

Write-Host "Notebook deployment complete. Item ID: $notebookId"
