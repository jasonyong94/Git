# Extract Apps/Functions and their Service Plans from Excel file
# Output: ServicePlanApps_Output.csv

$inputFile = Join-Path $PSScriptRoot "ProductionApps_20251120.xlsx"
$outputFile = Join-Path $PSScriptRoot "ServicePlanApps_Output.csv"

Write-Host "Opening Excel file: $inputFile" -ForegroundColor Cyan

# Open Excel file
$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$excel.DisplayAlerts = $false

try {
    $workbook = $excel.Workbooks.Open($inputFile)
    $worksheet = $workbook.Worksheets.Item(1)
    $usedRange = $worksheet.UsedRange
    $rows = $usedRange.Rows.Count
    
    Write-Host "Processing $rows rows..." -ForegroundColor Cyan
    
    # Process data
    $data = @()
    for ($row = 2; $row -le $rows; $row++) {
        $resourceType = $worksheet.Cells.Item($row, 3).Text
        $resourceName = $worksheet.Cells.Item($row, 2).Text
        $resourceGroup = $worksheet.Cells.Item($row, 1).Text
        
        # Filter for Web Apps and Function Apps
        if ($resourceType -like '*Microsoft.Web/sites*' -or 
            $resourceType -like '*functionapp*' -or 
            $resourceType -like '*webapp*') {
            
            # Extract service plan name from resource type
            $servicePlan = 'N/A'
            if ($resourceType -match 'serverfarms/([^/]+)') {
                $servicePlan = $matches[1]
            }
            
            $data += [PSCustomObject]@{
                ResourceGroup = $resourceGroup
                AppName = $resourceName
                ResourceType = $resourceType
                ServicePlan = $servicePlan
                Subscription = $worksheet.Cells.Item($row, 4).Text
                Region = $worksheet.Cells.Item($row, 5).Text
                Status = $worksheet.Cells.Item($row, 6).Text
            }
            
            Write-Host "  Found: $resourceName (Service Plan: $servicePlan)" -ForegroundColor Green
        }
    }
    
    # Close Excel
    $workbook.Close($false)
    
    # Export results
    $data | Export-Csv -Path $outputFile -NoTypeInformation
    
    Write-Host "`nResults exported to: $outputFile" -ForegroundColor Green
    Write-Host "Total apps/functions found: $($data.Count)" -ForegroundColor Green
    
    # Display summary
    Write-Host "`nSummary by Service Plan:" -ForegroundColor Cyan
    $data | Group-Object ServicePlan | Sort-Object Count -Descending | ForEach-Object {
        Write-Host "  $($_.Name): $($_.Count) app(s)" -ForegroundColor Yellow
    }
    
} catch {
    Write-Host "Error: $_" -ForegroundColor Red
} finally {
    $excel.Quit()
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
}
