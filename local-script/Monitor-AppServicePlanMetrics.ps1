<#
.SYNOPSIS
    Monitor Azure App Service Plans and display their SKU and auto-scale configuration.

.DESCRIPTION
    This script prompts for Azure login if needed, allows subscription selection, and retrieves
    all App Service Plans with their SKU details and auto-scale settings.

.PARAMETER OutputPath
    Path to save the detailed report CSV (default: Desktop)

.EXAMPLE
    .\Monitor-AppServicePlanMetrics.ps1

.NOTES
    Author: SRE Team
    Date: 2025-11-28
    Requires: Azure CLI
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$OutputPath = [Environment]::GetFolderPath('Desktop')
)

$ErrorActionPreference = 'Stop'

#region Helper Functions

function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = 'White'
    )
    Write-Host $Message -ForegroundColor $Color
}

function Test-AzureLogin {
    Write-ColorOutput "Checking Azure login status..." "Cyan"
    
    $account = az account show 2>$null
    
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($account)) {
        return $false
    }
    
    return $true
}

function Invoke-AzureLogin {
    Write-ColorOutput "`nYou need to log in to Azure." "Yellow"
    Write-ColorOutput "Opening browser for authentication...`n" "Gray"
    
    az login
    
    if ($LASTEXITCODE -ne 0) {
        Write-ColorOutput "Login failed. Please try again." "Red"
        return $false
    }
    
    Write-ColorOutput "✓ Login successful!`n" "Green"
    return $true
}

function Select-AzureSubscription {
    Write-ColorOutput "Fetching available Azure subscriptions..." "Cyan"
    
    $subscriptionsJson = az account list --output json 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($subscriptionsJson)) {
        Write-ColorOutput "Failed to retrieve subscriptions." "Red"
        return $null
    }
    
    $subscriptions = $subscriptionsJson | ConvertFrom-Json
    
    if ($subscriptions.Count -eq 0) {
        Write-ColorOutput "No subscriptions found." "Red"
        return $null
    }
    
    Write-ColorOutput "`n========================================" "Cyan"
    Write-ColorOutput "  Available Azure Subscriptions" "Cyan"
    Write-ColorOutput "========================================" "Cyan"
    
    $currentSub = ($subscriptions | Where-Object { $_.isDefault -eq $true })
    
    for ($i = 0; $i -lt $subscriptions.Count; $i++) {
        $sub = $subscriptions[$i]
        $marker = if ($sub.isDefault) { " [CURRENT]" } else { "" }
        $stateColor = switch ($sub.state) {
            "Enabled" { "Green" }
            "Warned" { "Yellow" }
            "Disabled" { "Red" }
            default { "Gray" }
        }
        
        Write-Host "  $($i + 1). " -NoNewline -ForegroundColor White
        Write-Host "$($sub.name)$marker" -ForegroundColor $stateColor
        Write-Host "     ID: $($sub.id)" -ForegroundColor Gray
        Write-Host "     State: $($sub.state)" -ForegroundColor $stateColor
        Write-Host ""
    }
    
    Write-ColorOutput "========================================`n" "Cyan"
    
    do {
        Write-Host "Select subscription number (1-$($subscriptions.Count)) or press Enter for current" -NoNewline -ForegroundColor Yellow
        if ($currentSub) {
            Write-Host " [$($currentSub.name)]" -NoNewline -ForegroundColor Cyan
        }
        Write-Host ": " -NoNewline
        
        $selection = Read-Host
        
        if ([string]::IsNullOrWhiteSpace($selection)) {
            if ($currentSub) {
                return $currentSub
            }
            else {
                Write-ColorOutput "No current subscription set. Please select a subscription." "Yellow"
                continue
            }
        }
        
        $selectionNum = 0
        if ([int]::TryParse($selection, [ref]$selectionNum)) {
            if ($selectionNum -ge 1 -and $selectionNum -le $subscriptions.Count) {
                return $subscriptions[$selectionNum - 1]
            }
        }
        
        Write-ColorOutput "Invalid selection. Please enter a number between 1 and $($subscriptions.Count)." "Red"
        
    } while ($true)
}

#endregion

#region Main Script

Write-ColorOutput "`n========================================" "Cyan"
Write-ColorOutput "  App Service Plan Configuration Report" "Cyan"
Write-ColorOutput "  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" "Cyan"
Write-ColorOutput "========================================`n" "Cyan"

# Check if logged in
if (-not (Test-AzureLogin)) {
    if (-not (Invoke-AzureLogin)) {
        Write-ColorOutput "Cannot proceed without Azure login. Exiting." "Red"
        exit 1
    }
}
else {
    Write-ColorOutput "✓ Already logged in to Azure`n" "Green"
}

# Select subscription
$selectedSub = Select-AzureSubscription

if (-not $selectedSub) {
    Write-ColorOutput "No subscription selected. Exiting." "Red"
    exit 1
}

# Set the selected subscription
Write-ColorOutput "Setting subscription context: $($selectedSub.name)" "Gray"
az account set --subscription $selectedSub.id

if ($LASTEXITCODE -ne 0) {
    Write-ColorOutput "Failed to set subscription. Exiting." "Red"
    exit 1
}

Write-ColorOutput "✓ Subscription set successfully`n" "Green"
Write-ColorOutput "Subscription: $($selectedSub.name)" "White"
Write-ColorOutput "ID: $($selectedSub.id)`n" "Gray"

# Get all App Service Plans
Write-ColorOutput "Querying App Service Plans..." "Cyan"

$plansJson = az appservice plan list --output json
if ($LASTEXITCODE -ne 0) {
    Write-ColorOutput "Failed to retrieve App Service Plans." "Red"
    exit 1
}

$plans = $plansJson | ConvertFrom-Json

if (-not $plans -or $plans.Count -eq 0) {
    Write-ColorOutput "No App Service Plans found in this subscription." "Yellow"
    exit 0
}

Write-ColorOutput "Found $($plans.Count) App Service Plans`n" "Green"

# Collect results
$results = @()

foreach ($plan in $plans) {
    Write-ColorOutput "Processing: $($plan.name)" "White"
    
    # Get auto-scale settings for this plan
    $autoScaleSettings = $null
    $autoScaleJson = az monitor autoscale list --resource-group $plan.resourceGroup --query "[?targetResourceUri=='$($plan.id)']" --output json 2>$null
    
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($autoScaleJson)) {
        $autoScaleSettings = $autoScaleJson | ConvertFrom-Json
    }
    
    # Extract auto-scale configuration
    $autoScaleEnabled = "No"
    $minInstances = "N/A"
    $maxInstances = $plan.maximumNumberOfWorkers
    $defaultInstances = $plan.numberOfWorkers
    $autoScaleRules = "None"
    
    if ($autoScaleSettings -and $autoScaleSettings.Count -gt 0) {
        $autoScaleSetting = $autoScaleSettings[0]
        $autoScaleEnabled = if ($autoScaleSetting.enabled) { "Yes" } else { "No" }
        
        if ($autoScaleSetting.profiles -and $autoScaleSetting.profiles.Count -gt 0) {
            $defaultProfile = $autoScaleSetting.profiles[0]
            $minInstances = $defaultProfile.capacity.minimum
            $maxInstances = $defaultProfile.capacity.maximum
            $defaultInstances = $defaultProfile.capacity.default
            
            if ($defaultProfile.rules -and $defaultProfile.rules.Count -gt 0) {
                $ruleDescriptions = $defaultProfile.rules | ForEach-Object {
                    $metric = $_.metricTrigger.metricName
                    $operator = $_.metricTrigger.operator
                    $threshold = $_.metricTrigger.threshold
                    $direction = $_.scaleAction.direction
                    $value = $_.scaleAction.value
                    "$metric $operator $threshold% -> $direction by $value"
                }
                $autoScaleRules = $ruleDescriptions -join "; "
            }
        }
    }
    
    Write-ColorOutput "  SKU: $($plan.sku.tier) ($($plan.sku.name))" "Gray"
    Write-ColorOutput "  Current: $defaultInstances, Min: $minInstances, Max: $maxInstances" "Gray"
    Write-ColorOutput "  Auto-scale: $autoScaleEnabled" "Gray"
    Write-Host ""
    
    $result = [PSCustomObject]@{
        AppServicePlan = $plan.name
        ResourceGroup = $plan.resourceGroup
        Location = $plan.location
        SKU_Tier = $plan.sku.tier
        SKU_Name = $plan.sku.name
        SKU_Capacity = $plan.sku.capacity
        Current_Instances = $defaultInstances
        Min_Instances = $minInstances
        Max_Instances = $maxInstances
        AutoScale_Enabled = $autoScaleEnabled
        AutoScale_Rules = $autoScaleRules
        Kind = $plan.kind
        Status = $plan.status
        ResourceId = $plan.id
    }
    
    $results += $result
}

# Export to CSV
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$csvPath = Join-Path $OutputPath "AppServicePlan_Configuration_$timestamp.csv"
$results | Export-Csv -Path $csvPath -NoTypeInformation

Write-ColorOutput "========================================" "Cyan"
Write-ColorOutput "  Report Complete" "Cyan"
Write-ColorOutput "========================================`n" "Cyan"

Write-ColorOutput "Total Plans: $($results.Count)" "White"
Write-ColorOutput "Report saved to: $csvPath`n" "Green"

# Display summary table
Write-ColorOutput "Summary:" "Cyan"
$results | Format-Table -Property AppServicePlan, SKU_Tier, SKU_Name, Current_Instances, Min_Instances, Max_Instances, AutoScale_Enabled -AutoSize

Write-ColorOutput "`nDetailed CSV report saved to Desktop." "Green"

return $results

#endregion
