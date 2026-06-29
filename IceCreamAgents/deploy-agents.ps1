#requires -Version 7
<#
.SYNOPSIS
  Redeploy the IceCream agents (prompt agents) to any Microsoft Foundry project.

.DESCRIPTION
  Pushes IceCreamOperator and IceCreamFactoryManagerV2 to the target project via the
  Foundry agents REST API. Operator is deployed first because the Manager references it
  through the a2a-IceCreamOperator connection.

  Prerequisites in the TARGET project (see connections.json):
    - The model deployments named in each definition.json exist (or pass -ModelOverride).
    - The project connections in connections.json have been recreated (with secrets).

.EXAMPLE
  ./deploy-agents.ps1 -ProjectEndpoint "https://my-foundry.services.ai.azure.com/api/projects/my-proj"
#>
param(
  [Parameter(Mandatory = $true)][string]$ProjectEndpoint,
  [string]$ApiVersion = "2025-05-01",
  [string]$ModelOverride
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$agents = @("IceCreamOperator", "IceCreamFactoryManagerV2")  # order matters

$token = (az account get-access-token --resource "https://ai.azure.com" --query accessToken -o tsv)
if (-not $token) { throw "Could not get access token. Run 'az login' first." }

foreach ($name in $agents) {
  $defPath = Join-Path $root "$name/definition.json"
  $def = Get-Content $defPath -Raw | ConvertFrom-Json
  if ($ModelOverride) { $def.model = $ModelOverride }
  $body = @{ name = $name; definition = $def } | ConvertTo-Json -Depth 20
  $uri = "$($ProjectEndpoint.TrimEnd('/'))/agents/$name`?api-version=$ApiVersion"
  Write-Host "Deploying $name -> $uri"
  $body | az rest --method put --uri $uri --headers "Authorization=Bearer $token" "Content-Type=application/json" --body "@-" | Out-Null
  Write-Host "  $name deployed."
}
Write-Host "Done. Both agents deployed to $ProjectEndpoint"
