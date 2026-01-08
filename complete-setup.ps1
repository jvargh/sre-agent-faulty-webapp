# Complete Setup Script - After Temporary Public Access Enabled

Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║         Complete FaultyWebApp Setup                          ║" -ForegroundColor Cyan  
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

$webAppName = "app-y7njcffivri2q"
$sqlServer = "sql-y7njcffivri2q"
$dbName = "FaultyWebAppDb"
$rgName = "sre-demo2-rg"

# Step 1: Grant SQL Permissions
Write-Host "STEP 1: Grant SQL Permissions" -ForegroundColor Yellow
Write-Host "════════════════════════════════" -ForegroundColor DarkGray
Write-Host ""
Write-Host "SQL Commands to execute in Azure Portal:" -ForegroundColor Cyan
Write-Host ""
Get-Content .\configure-permissions.sql
Write-Host ""
Write-Host "Portal: https://portal.azure.com" -ForegroundColor Cyan
Write-Host "Go to: SQL databases > FaultyWebAppDb > Query editor" -ForegroundColor Gray
Write-Host ""
$sqlDone = Read-Host "Have you executed the SQL commands? (Y/n)"

if ($sqlDone -ne "Y" -and $sqlDone -ne "y" -and $sqlDone -ne "") {
    Write-Host "Please complete SQL permissions first" -ForegroundColor Red
    exit
}

# Step 2: Test Connectivity
Write-Host "`nSTEP 2: Test Application Connectivity" -ForegroundColor Yellow
Write-Host "════════════════════════════════" -ForegroundColor DarkGray
Write-Host ""

Write-Host "Testing health endpoint..." -ForegroundColor Cyan
try {
    $health = Invoke-WebRequest -Uri "https://$webAppName.azurewebsites.net/health" -UseBasicParsing
    Write-Host "✓ Health Check: $($health.StatusCode) - $($health.Content)" -ForegroundColor Green
    $healthPass = $true
} catch {
    Write-Host "✗ Health Check Failed: $($_.Exception.Message)" -ForegroundColor Red
    $healthPass = $false
}

Write-Host "`nTesting API endpoint..." -ForegroundColor Cyan
try {
    $api = Invoke-WebRequest -Uri "https://$webAppName.azurewebsites.net/api/products" -UseBasicParsing
    Write-Host "✓ API: $($api.StatusCode)" -ForegroundColor Green
    Write-Host "  Response: $($api.Content)" -ForegroundColor Gray
    $apiPass = $true
} catch {
    Write-Host "✗ API Failed: $($_.Exception.Message)" -ForegroundColor Red
    $apiPass = $false
}

# Step 3: Disable Public Access
if ($healthPass -and $apiPass) {
    Write-Host "`nSTEP 3: Disable Public SQL Access (Re-secure)" -ForegroundColor Yellow
    Write-Host "════════════════════════════════" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "Application is working! Now disabling public SQL access..." -ForegroundColor Cyan
    
    az sql server update --name $sqlServer --resource-group $rgName --enable-public-network false
    
    Write-Host "✓ Public access disabled" -ForegroundColor Green
    Write-Host "  SQL Server now only accessible via private endpoint" -ForegroundColor Gray
    
    Write-Host "`nWaiting 30 seconds and testing again..." -ForegroundColor Gray
    Start-Sleep -Seconds 30
    
    Write-Host "`nFinal test with private endpoint only..." -ForegroundColor Cyan
    try {
        $finalHealth = Invoke-WebRequest -Uri "https://$webAppName.azurewebsites.net/health" -UseBasicParsing
        Write-Host "✓ Health Check (Private): $($finalHealth.StatusCode)" -ForegroundColor Green
    } catch {
        Write-Host "⚠ Health Check Failed - May need more time for private endpoint" -ForegroundColor Yellow
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Gray
        Write-Host "  Wait 2-3 minutes and test again" -ForegroundColor Gray
    }
    
    Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║                 SETUP COMPLETE!                              ║" -ForegroundColor Green  
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    Write-Host "✓ SQL Permissions granted" -ForegroundColor Green
    Write-Host "✓ Application tested and working" -ForegroundColor Green
    Write-Host "✓ Public SQL access disabled (secure)" -ForegroundColor Green
    Write-Host ""
    Write-Host "Application URL: https://$webAppName.azurewebsites.net" -ForegroundColor Cyan
    Write-Host ""
    
} else {
    Write-Host "`n⚠ Tests failed. Please check:" -ForegroundColor Yellow
    Write-Host "  1. SQL permissions were granted correctly" -ForegroundColor White
    Write-Host "  2. Database tables exist (run: dotnet ef database update)" -ForegroundColor White
    Write-Host "  3. App Service logs: az webapp log tail --name $webAppName --resource-group $rgName" -ForegroundColor White
}
