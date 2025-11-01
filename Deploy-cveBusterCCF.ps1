<#
.SYNOPSIS
    Deploy cveBuster CCF Connector to Microsoft Sentinel

.DESCRIPTION
    This script deploys all necessary components for the cveBuster Codeless Connector Framework (CCF):
    - Data Collection Endpoint (DCE)
    - Custom Log Analytics Table
    - Data Collection Rule (DCR)
    - Data Connector Poller

.NOTES
    Author: 
    Date: 
    Version: 1.0
#>

# ============================================================================
# MODULE REQUIREMENTS - Auto-import required modules
# ============================================================================
$requiredModules = @('Az.Accounts', 'Az.OperationalInsights', 'Az.Monitor', 'Az.Resources')
foreach ($module in $requiredModules) {
    if (-not (Get-Module -Name $module -ListAvailable)) {
        Write-Host "❌ Module '$module' is not installed. Please run: Install-Module -Name $module -Scope CurrentUser" -ForegroundColor Red
        exit 1
    }
    Import-Module $module -ErrorAction Stop
}

# ============================================================================
# CONFIGURATION SECTION - UPDATE THESE VALUES AS NEEDED
# ============================================================================

# Azure Subscription & Resource Group
$SubscriptionId = ""
$ResourceGroupName = ""
$Location = ""

# Microsoft Sentinel Workspace
$WorkspaceName = ""
$WorkspaceId = ""

# cveBuster API Configuration
$ApiEndpoint = ""
$ApiKey = ""

# Component Names (customize if needed)
$DceName = ""
$DcrName = ""
$TableName = ""
$PollerName = ""
$StreamName = ""

# Script Behavior
$DeployDCE = $true
$SkipConfirmation = $false

# ============================================================================
# DO NOT MODIFY BELOW THIS LINE UNLESS YOU KNOW WHAT YOU'RE DOING
# ============================================================================

$ErrorActionPreference = "Stop"

function Write-Status {
    param(
        [string]$Message,
        [string]$Type = "Info"
    )
    
    switch ($Type) {
        "Success" { Write-Host "✅ $Message" -ForegroundColor Green }
        "Error"   { Write-Host "❌ $Message" -ForegroundColor Red }
        "Warning" { Write-Host "⚠️  $Message" -ForegroundColor Yellow }
        "Info"    { Write-Host "ℹ️  $Message" -ForegroundColor Cyan }
        "Step"    { Write-Host "`n🔹 $Message" -ForegroundColor Magenta }
        default   { Write-Host $Message }
    }
}

Write-Host "`n" -NoNewline
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   cveBuster CCF Connector - Deployment Script" -ForegroundColor White
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

Write-Status "Deployment Configuration:" "Info"
Write-Host "  Subscription ID   : $SubscriptionId" -ForegroundColor Gray
Write-Host "  Resource Group    : $ResourceGroupName" -ForegroundColor Gray
Write-Host "  Location          : $Location" -ForegroundColor Gray
Write-Host "  Workspace Name    : $WorkspaceName" -ForegroundColor Gray
Write-Host "  API Endpoint      : $ApiEndpoint" -ForegroundColor Gray
Write-Host ""

if (-not $SkipConfirmation) {
    $confirm = Read-Host "Do you want to proceed with deployment? (Y/N)"
    if ($confirm -ne 'Y' -and $confirm -ne 'y') {
        Write-Status "Deployment cancelled by user." "Warning"
        exit 0
    }
}

try {
    Write-Status "Connecting to Azure..." "Step"
    $context = Get-AzContext
    if (-not $context) {
        Write-Status "No Azure context found. Please sign in..." "Warning"
        Connect-AzAccount
        $context = Get-AzContext
    }
    
    if ($context.Subscription.Id -ne $SubscriptionId -and $SubscriptionId -ne "") {
        Write-Status "Switching to subscription: $SubscriptionId" "Info"
        Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
    }
    
    Write-Status "Connected to Azure (Subscription: $($context.Subscription.Name))" "Success"

    Write-Status "Verifying Log Analytics Workspace..." "Step"
    $workspace = Get-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroupName -Name $WorkspaceName -ErrorAction SilentlyContinue
    if (-not $workspace) {
        throw "Workspace '$WorkspaceName' not found in resource group '$ResourceGroupName'"
    }
    $WorkspaceResourceId = $workspace.ResourceId
    Write-Status "Workspace verified: $WorkspaceName" "Success"

    if ($DeployDCE) {
        Write-Status "Creating Data Collection Endpoint..." "Step"
        $dce = Get-AzDataCollectionEndpoint -ResourceGroupName $ResourceGroupName -Name $DceName -ErrorAction SilentlyContinue
        if ($dce) {
            Write-Status "DCE '$DceName' already exists. Skipping creation." "Warning"
            $DceResourceId = $dce.Id
        } else {
            $dceParams = @{
                Name = $DceName
                ResourceGroupName = $ResourceGroupName
                Location = $Location
                NetworkAclsPublicNetworkAccess = "Enabled"
            }
            $dce = New-AzDataCollectionEndpoint @dceParams
            $DceResourceId = $dce.Id
            Write-Status "DCE created: $DceName" "Success"
        }
    }

    Write-Status "Creating Custom Log Analytics Table..." "Step"
    $tableJsonPath = Join-Path $PSScriptRoot "Table.json"
    if (-not (Test-Path $tableJsonPath)) { throw "Table.json not found at: $tableJsonPath" }
    $tableSchema = Get-Content $tableJsonPath -Raw | ConvertFrom-Json
    $tableUri = "$WorkspaceResourceId/tables/$($TableName)?api-version=2022-10-01"
    $tableBody = @{ properties = $tableSchema.properties } | ConvertTo-Json -Depth 10
    $response = Invoke-AzRestMethod -Path $tableUri -Method PUT -Payload $tableBody

    Write-Status "Creating Data Collection Rule..." "Step"
    $dcrJsonPath = Join-Path $PSScriptRoot "DCR.json"
    $
