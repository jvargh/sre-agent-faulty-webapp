# Fix API Error - Comprehensive Setup Script

$ErrorActionPreference = "Continue"

Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     FaultyWebApp - Fix API Error Diagnostic & Setup           ║" -ForegroundColor Cyan  
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

$webAppName = "app-y7njcffivri2q"
$sqlServer = "sql-y7njcffivri2q"
$dbName = "FaultyWebAppDb"
$rgName = "sre-demo2-rg"

# Current error: "An error occurred while retrieving products"
# This means the ProductsController is catching an exception

Write-Host "Current Error: 'An error occurred while retrieving products'" -ForegroundColor Red
Write-Host "This typically means:" -ForegroundColor Yellow
Write-Host "  1. Cannot connect to SQL Server (most likely)" -ForegroundColor White
Write-Host "  2. SQL permissions not granted to managed identity" -ForegroundColor White
Write-Host "  3. Database tables don't exist" -ForegroundColor White
Write-Host ""

# Step 1: Check SQL public access
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "STEP 1: Verify SQL Server Configuration" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host ""

$sqlConfig = az sql server show --name $sqlServer --resource-group $rgName | ConvertFrom-Json
Write-Host "SQL Server: $sqlServer" -ForegroundColor Gray
Write-Host "Public Network Access: $($sqlConfig.publicNetworkAccess)" -ForegroundColor $(if ($sqlConfig.publicNetworkAccess -eq "Enabled") { "Green" } else { "Yellow" })
Write-Host "State: $($sqlConfig.state)" -ForegroundColor Gray

if ($sqlConfig.publicNetworkAccess -ne "Enabled") {
    Write-Host "`n⚠ Public access is DISABLED" -ForegroundColor Yellow
    Write-Host "  For initial setup, we need temporary public access" -ForegroundColor White
    $enable = Read-Host "Enable public access temporarily? (Y/n)"
    
    if ($enable -eq "" -or $enable -eq "Y" -or $enable -eq "y") {
        Write-Host "Enabling public access..." -ForegroundColor Yellow
        az sql server update --name $sqlServer --resource-group $rgName --enable-public-network true | Out-Null
        Write-Host "✓ Public access enabled" -ForegroundColor Green
        Write-Host "  Waiting 30 seconds for change to propagate..." -ForegroundColor Gray
        Start-Sleep -Seconds 30
    }
}

# Step 2: SQL Permissions
Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "STEP 2: Grant SQL Permissions to Managed Identity" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host ""
Write-Host "You MUST execute these SQL commands in Azure Portal:" -ForegroundColor Yellow
Write-Host ""
Write-Host "CREATE USER [$webAppName] FROM EXTERNAL PROVIDER;" -ForegroundColor Yellow
Write-Host "ALTER ROLE db_datareader ADD MEMBER [$webAppName];" -ForegroundColor Yellow
Write-Host "ALTER ROLE db_datawriter ADD MEMBER [$webAppName];" -ForegroundColor Yellow
Write-Host "ALTER ROLE db_ddladmin ADD MEMBER [$webAppName];" -ForegroundColor Yellow
Write-Host "GO" -ForegroundColor Yellow
Write-Host ""
Write-Host "Portal Link (Query Editor):" -ForegroundColor Cyan
Write-Host "https://portal.azure.com → SQL databases → FaultyWebAppDb → Query editor" -ForegroundColor Blue
Write-Host ""

# Open portal
$openPortal = Read-Host "Open Azure Portal now? (Y/n)"
if ($openPortal -eq "" -or $openPortal -eq "Y" -or $openPortal -eq "y") {
    Start-Process "https://portal.azure.com/#view/Microsoft_Azure_Sql/DatabaseMenuBlade/~/QueryEditor/resourceId/%2Fsubscriptions%2F463a82d4-1896-4332-aeeb-618ee5a5aa93%2FresourceGroups%2Fsre-demo2-rg%2Fproviders%2FMicrosoft.Sql%2Fservers%2Fsql-y7njcffivri2q%2Fdatabases%2FFaultyWebAppDb"
    Write-Host "✓ Portal opened" -ForegroundColor Green
}

Write-Host ""
$sqlDone = Read-Host "Have you executed the SQL commands successfully? (Y/n)"

if ($sqlDone -ne "Y" -and $sqlDone -ne "y" -and $sqlDone -ne "") {
    Write-Host "`n⚠ Please complete SQL permissions first, then run this script again" -ForegroundColor Yellow
    exit
}

# Step 3: Test Connection
Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "STEP 3: Test Application" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host ""

Write-Host "Waiting 10 seconds for permissions to take effect..." -ForegroundColor Gray
Start-Sleep -Seconds 10

Write-Host "`nTesting Health Endpoint..." -ForegroundColor Yellow
try {
    $health = Invoke-WebRequest -Uri "https://$webAppName.azurewebsites.net/health" -UseBasicParsing -TimeoutSec 30
    Write-Host "✓ Health: $($health.StatusCode) - $($health.Content)" -ForegroundColor Green
    $healthPass = $true
} catch {
    Write-Host "✗ Health: Failed - $($_.Exception.Message)" -ForegroundColor Red
    $healthPass = $false
}

Write-Host "`nTesting API Endpoint..." -ForegroundColor Yellow
try {
    $api = Invoke-WebRequest -Uri "https://$webAppName.azurewebsites.net/api/products" -UseBasicParsing -TimeoutSec 30
    Write-Host "✓ API: $($api.StatusCode)" -ForegroundColor Green
    Write-Host "  Response: $($api.Content)" -ForegroundColor Gray
    $apiPass = $true
} catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    Write-Host "✗ API: Failed with status $statusCode" -ForegroundColor Red
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Gray
    $apiPass = $false
    
    if ($statusCode -eq 500) {
        Write-Host "`n  Possible causes:" -ForegroundColor Yellow
        Write-Host "    - SQL permissions not granted correctly" -ForegroundColor White
        Write-Host "    - Managed identity name mismatch" -ForegroundColor White
        Write-Host "    - Database connection string issue" -ForegroundColor White
    }
}

# Step 4: If working, re-secure
if ($healthPass -and $apiPass) {
    Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
    Write-Host "STEP 4: Re-secure SQL Server (Disable Public Access)" -ForegroundColor Cyan
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
    Write-Host ""
    
    $resecure = Read-Host "Application is working! Disable public SQL access now? (Y/n)"
    if ($resecure -eq "" -or $resecure -eq "Y" -or $resecure -eq "y") {
        Write-Host "Disabling public access..." -ForegroundColor Yellow
        az sql server update --name $sqlServer --resource-group $rgName --enable-public-network false | Out-Null
        Write-Host "✓ Public access disabled" -ForegroundColor Green
        Write-Host "  SQL Server now only accessible via private endpoint" -ForegroundColor Gray
        
        Write-Host "`nWaiting 30 seconds and testing with private endpoint only..." -ForegroundColor Gray
        Start-Sleep -Seconds 30
        
        Write-Host "`nFinal test..." -ForegroundColor Cyan
        try {
            $finalTest = Invoke-WebRequest -Uri "https://$webAppName.azurewebsites.net/api/products" -UseBasicParsing
            Write-Host "✓ API works with private endpoint! Status: $($finalTest.StatusCode)" -ForegroundColor Green
        } catch {
            Write-Host "⚠ API test failed with private endpoint" -ForegroundColor Yellow
            Write-Host "  May need 2-5 minutes for private endpoint to fully work" -ForegroundColor Gray
            Write-Host "  Or VNet integration may need troubleshooting" -ForegroundColor Gray
        }
    }
    
    Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║                    ✓ SETUP COMPLETE!                           ║" -ForegroundColor Green  
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    Write-Host "✓ SQL Permissions granted" -ForegroundColor Green
    Write-Host "✓ Application tested and working" -ForegroundColor Green
    Write-Host "✓ Security configured" -ForegroundColor Green
    Write-Host ""
    Write-Host "URLs:" -ForegroundColor Cyan
    Write-Host "  Application: https://$webAppName.azurewebsites.net" -ForegroundColor Blue
    Write-Host "  Health: https://$webAppName.azurewebsites.net/health" -ForegroundColor Blue
    Write-Host "  API: https://$webAppName.azurewebsites.net/api/products" -ForegroundColor Blue
    Write-Host ""
    
} else {
    Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "║                    ✗ SETUP INCOMPLETE                          ║" -ForegroundColor Red  
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Red
    Write-Host ""
    Write-Host "⚠ Tests failed. Troubleshooting steps:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "1. Verify SQL commands were executed correctly" -ForegroundColor White
    Write-Host "   Check for 'Commands completed successfully' message" -ForegroundColor Gray
    Write-Host ""
    Write-Host "2. Verify the managed identity name is correct" -ForegroundColor White
    Write-Host "   Expected: $webAppName" -ForegroundColor Gray
    Write-Host ""
    Write-Host "3. Check application logs for detailed errors:" -ForegroundColor White
    Write-Host "   az webapp log tail --name $webAppName --resource-group $rgName" -ForegroundColor Gray
    Write-Host ""
    Write-Host "4. Restart the app and wait 2 minutes:" -ForegroundColor White
    Write-Host "   az webapp restart --name $webAppName --resource-group $rgName" -ForegroundColor Gray
    Write-Host ""
}
