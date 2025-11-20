# Get all Apps/Functions and their Service Plans using Azure CLI
# Output: ServicePlanApps_Output.csv

$outputFile = Join-Path $PSScriptRoot "ServicePlanApps_Output.csv"

Write-Host "Querying Azure for all Web Apps and Function Apps..." -ForegroundColor Cyan
Write-Host "This may take a moment..." -ForegroundColor Yellow

# Query all web apps
Write-Host "Fetching Web Apps..." -ForegroundColor Gray
$webApps = az webapp list --query "[].{Name:name, ResourceGroup:resourceGroup, ServicePlan:appServicePlanId, Type:kind, State:state, Location:location, DefaultHostName:defaultHostName, ResourceType:'WebApp'}" -o json | ConvertFrom-Json

# Query all function apps
Write-Host "Fetching Function Apps..." -ForegroundColor Gray
$functionApps = az functionapp list --query "[].{Name:name, ResourceGroup:resourceGroup, ServicePlan:appServicePlanId, Type:kind, State:state, Location:location, DefaultHostName:defaultHostName, ResourceType:'FunctionApp'}" -o json | ConvertFrom-Json

# Combine both lists
$apps = @()
if ($webApps) { $apps += $webApps }
if ($functionApps) { $apps += $functionApps }

if ($apps) {
    Write-Host "Found $($apps.Count) apps/functions" -ForegroundColor Green
    
    # Process the data
    $data = @()
    foreach ($app in $apps) {
        # Extract service plan name from the full resource ID
        $servicePlanName = if ($app.ServicePlan -match '/serverfarms/([^/]+)$') {
            $matches[1]
        } else {
            'Unknown'
        }
        
        # Extract subscription from service plan ID
        $subscription = if ($app.ServicePlan -match '/subscriptions/([^/]+)/') {
            $matches[1]
        } else {
            'Unknown'
        }
        
        $data += [PSCustomObject]@{
            AppName = $app.Name
            ResourceGroup = $app.ResourceGroup
            ServicePlan = $servicePlanName
            ResourceType = $app.ResourceType
            Kind = $app.Type
            State = $app.State
            Location = $app.Location
            Subscription = $subscription
            DefaultHostName = $app.DefaultHostName
        }
        
        Write-Host "  $($app.Name) -> $servicePlanName" -ForegroundColor Gray
    }
    
    # Export to CSV
    $data | Export-Csv -Path $outputFile -NoTypeInformation
    
    Write-Host "`nResults exported to: $outputFile" -ForegroundColor Green
    Write-Host "Total apps/functions found: $($data.Count)" -ForegroundColor Green
    
    # Display summary by service plan
    Write-Host "`nSummary by Service Plan:" -ForegroundColor Cyan
    $data | Group-Object ServicePlan | Sort-Object Count -Descending | ForEach-Object {
        Write-Host "  $($_.Name): $($_.Count) app(s)" -ForegroundColor Yellow
    }
    
    # Display summary by type
    Write-Host "`nSummary by Resource Type:" -ForegroundColor Cyan
    $data | Group-Object ResourceType | Sort-Object Count -Descending | ForEach-Object {
        Write-Host "  $($_.Name): $($_.Count) app(s)" -ForegroundColor Yellow
    }
    
    Write-Host "`nSummary by Kind:" -ForegroundColor Cyan
    $data | Group-Object Kind | Sort-Object Count -Descending | ForEach-Object {
        Write-Host "  $($_.Name): $($_.Count) app(s)" -ForegroundColor Yellow
    }
    
} else {
    Write-Host "No apps/functions found or Azure CLI error" -ForegroundColor Red
    Write-Host "Make sure you're logged in: az login" -ForegroundColor Yellow
}
