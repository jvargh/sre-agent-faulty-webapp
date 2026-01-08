# Break/Fix Script for FaultyWebApp
# This script can deliberately introduce errors and remediate them

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("break", "fix", "diagnose")]
    [string]$Action,
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroup = "sre-demo2-rg",
    
    [Parameter(Mandatory=$false)]
    [string]$SqlServerName = "sql-y7njcffivri2q",
    
    [Parameter(Mandatory=$false)]
    [string]$AppServiceName = "app-y7njcffivri2q",
    
    [Parameter(Mandatory=$false)]
    [string]$VNetName = "vnet-y7njcffivri2q",
    
    [Parameter(Mandatory=$false)]
    [string]$DatabaseName = "FaultyWebAppDb"
)

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  FaultyWebApp Break/Fix Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Action: $Action" -ForegroundColor Yellow
Write-Host "Resource Group: $ResourceGroup" -ForegroundColor Gray
Write-Host ""

# Get the private DNS zone name
$privateDnsZoneName = "privatelink.database.windows.net"

# Get the managed identity principal ID
Write-Host "Getting managed identity information..." -ForegroundColor Cyan
$managedIdentity = az webapp identity show --name $AppServiceName --resource-group $ResourceGroup | ConvertFrom-Json

if ($null -eq $managedIdentity -or $null -eq $managedIdentity.principalId) {
    Write-Host "ERROR: Could not retrieve managed identity for $AppServiceName" -ForegroundColor Red
    exit 1
}

$principalId = $managedIdentity.principalId
Write-Host "Managed Identity Principal ID: $principalId" -ForegroundColor Green
Write-Host ""

# Function to diagnose the system
function Invoke-Diagnose {
    Write-Host "🔍 DIAGNOSING THE SYSTEM..." -ForegroundColor Cyan
    Write-Host ""
    
    $issues = @()
    
    # Check #1: VNet Link Status
    Write-Host "[1/4] Checking Private DNS Zone VNet Link..." -ForegroundColor Yellow
    $vnetLinks = az network private-dns link vnet list `
        --resource-group $ResourceGroup `
        --zone-name $privateDnsZoneName `
        --query "[].{name:name, vnetId:virtualNetwork.id, provisioningState:provisioningState}" -o json | ConvertFrom-Json
    
    if ($vnetLinks.Count -eq 0) {
        Write-Host "  ❌ ISSUE: No VNet links found in Private DNS Zone" -ForegroundColor Red
        Write-Host "     Impact: DNS resolution for private endpoint will fail" -ForegroundColor DarkRed
        $issues += "Private DNS Zone VNet Link Missing"
    } else {
        Write-Host "  ✓ VNet link exists: $($vnetLinks[0].name) ($($vnetLinks[0].provisioningState))" -ForegroundColor Green
    }
    Write-Host ""
    
    # Check #2: App Service Configuration
    Write-Host "[2/4] Checking App Service Configuration..." -ForegroundColor Yellow
    $appConfig = az webapp config appsettings list `
        --name $AppServiceName `
        --resource-group $ResourceGroup `
        --query "[?name=='ConnectionStrings__DefaultConnection'].{name:name, value:value}" -o json | ConvertFrom-Json
    
    if ($appConfig.Count -gt 0) {
        $connString = $appConfig[0].value
        Write-Host "  ✓ Connection string configured in app settings" -ForegroundColor Green
        if ($connString -like "*Authentication=Active Directory Default*") {
            Write-Host "  ✓ Connection string includes 'Authentication=Active Directory Default'" -ForegroundColor Green
        } else {
            Write-Host "  ⚠ Connection string may not have proper Azure AD authentication" -ForegroundColor Yellow
            Write-Host "     Current: $connString" -ForegroundColor Gray
        }
    } else {
        Write-Host "  ℹ Connection string not in app settings (using appsettings.json)" -ForegroundColor Cyan
        Write-Host "     This is expected - connection string loaded from deployed config" -ForegroundColor DarkGray
    }
    Write-Host ""
    
    # Check #3: SQL Database User
    Write-Host "[3/4] Checking SQL Database User..." -ForegroundColor Yellow
    $sqlServer = az sql server show --name $SqlServerName --resource-group $ResourceGroup | ConvertFrom-Json
    $sqlServerFqdn = $sqlServer.fullyQualifiedDomainName
    Write-Host "  SQL Server: $sqlServerFqdn" -ForegroundColor Gray
    Write-Host "  Managed Identity: $AppServiceName" -ForegroundColor Gray
    Write-Host "  Note: Cannot automatically verify SQL user without executing query" -ForegroundColor DarkGray
    Write-Host ""
    
    # Check #4: Health Endpoint
    Write-Host "[4/4] Testing Health Endpoint..." -ForegroundColor Yellow
    $healthUrl = "https://$AppServiceName.azurewebsites.net/health/sql"
    Write-Host "  Testing: $healthUrl" -ForegroundColor Gray
    
    try {
        $response = Invoke-RestMethod -Uri $healthUrl -Method Get -ErrorAction Stop
        
        if ($response.status -eq "healthy") {
            Write-Host "  ✓ Health check PASSED" -ForegroundColor Green
            Write-Host "     Status: $($response.status)" -ForegroundColor Gray
            Write-Host "     Connection State: $($response.connectionState)" -ForegroundColor Gray
            Write-Host "     Database: $($response.database)" -ForegroundColor Gray
        } else {
            Write-Host "  ❌ Health check FAILED" -ForegroundColor Red
            Write-Host "     Status: $($response.status)" -ForegroundColor DarkRed
            Write-Host "     Error: $($response.error)" -ForegroundColor DarkRed
            Write-Host "     Error Type: $($response.errorType)" -ForegroundColor DarkRed
            if ($response.errorNumber) {
                Write-Host "     Error Number: $($response.errorNumber)" -ForegroundColor DarkRed
            }
            
            # Analyze the error
            if ($response.errorType -eq "SqlException" -and $response.error -like "*Login failed*") {
                Write-Host ""
                Write-Host "  Root Cause Analysis:" -ForegroundColor Yellow
                Write-Host "     • Managed identity user not created in SQL Database" -ForegroundColor Gray
                Write-Host "     • User '$AppServiceName' does not have SQL permissions" -ForegroundColor Gray
                $issues += "Managed Identity SQL User Missing"
            }
            
            if ($response.error -like "*network*" -or $response.error -like "*DNS*" -or $response.error -like "*resolve*") {
                Write-Host ""
                Write-Host "  Root Cause Analysis:" -ForegroundColor Yellow
                Write-Host "     • DNS resolution likely failing" -ForegroundColor Gray
                Write-Host "     • Private DNS Zone may not be linked to VNet" -ForegroundColor Gray
                $issues += "DNS Resolution Failure"
            }
        }
    }
    catch {
        Write-Host "  ❌ Could not reach health endpoint" -ForegroundColor Red
        Write-Host "     Error: $($_.Exception.Message)" -ForegroundColor DarkRed
        $issues += "Health Endpoint Unreachable"
    }
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  DIAGNOSIS COMPLETE" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    if ($issues.Count -eq 0) {
        Write-Host "✅ No issues detected - System is healthy!" -ForegroundColor Green
    } else {
        Write-Host "⚠️  Issues Found: $($issues.Count)" -ForegroundColor Yellow
        foreach ($issue in $issues) {
            Write-Host "  • $issue" -ForegroundColor Red
        }
        Write-Host ""
        Write-Host "Run with '-Action fix' to remediate these issues" -ForegroundColor Cyan
    }
    Write-Host ""
}

# Function to break the system
function Invoke-Break {
    Write-Host "🔴 BREAKING THE SYSTEM..." -ForegroundColor Red
    Write-Host ""
    
    # Break #1: Remove Private DNS Zone VNet Link
    Write-Host "[1/2] Removing Private DNS Zone VNet link..." -ForegroundColor Yellow
    
    $vnetLinks = az network private-dns link vnet list `
        --resource-group $ResourceGroup `
        --zone-name $privateDnsZoneName `
        --query "[].{name:name, vnetId:virtualNetwork.id}" -o json | ConvertFrom-Json
    
    if ($vnetLinks.Count -gt 0) {
        foreach ($link in $vnetLinks) {
            Write-Host "  Deleting VNet link: $($link.name)" -ForegroundColor Gray
            az network private-dns link vnet delete `
                --resource-group $ResourceGroup `
                --zone-name $privateDnsZoneName `
                --name $link.name `
                --yes 2>&1 | Out-Null
        }
        Write-Host "  ✓ Private DNS Zone VNet link removed" -ForegroundColor Red
        Write-Host "  Impact: SQL Server private endpoint DNS resolution will fail" -ForegroundColor DarkRed
    } else {
        Write-Host "  ⚠ No VNet links found (already broken?)" -ForegroundColor Yellow
    }
    
    Write-Host ""
    
    # Break #2: Remove Managed Identity SQL User
    Write-Host "[2/2] Removing managed identity from SQL Database..." -ForegroundColor Yellow
    
    # Get SQL Server FQDN
    $sqlServer = az sql server show --name $SqlServerName --resource-group $ResourceGroup | ConvertFrom-Json
    $sqlServerFqdn = $sqlServer.fullyQualifiedDomainName
    
    Write-Host "  Connecting to SQL Server: $sqlServerFqdn" -ForegroundColor Gray
    
    # Create temporary SQL script to drop user
    $dropUserSql = @"
-- Drop managed identity user
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = '$AppServiceName')
BEGIN
    DROP USER [$AppServiceName];
    PRINT 'User [$AppServiceName] dropped successfully';
END
ELSE
BEGIN
    PRINT 'User [$AppServiceName] does not exist';
END
GO
"@
    
    $sqlScriptPath = Join-Path $env:TEMP "drop_sql_user.sql"
    $dropUserSql | Out-File -FilePath $sqlScriptPath -Encoding UTF8
    
    Write-Host "  Executing SQL command to drop user..." -ForegroundColor Gray
    Write-Host "  Note: This requires Azure AD authentication to SQL Server" -ForegroundColor DarkGray
    
    # Try to execute using Azure CLI
    try {
        $result = az sql db query `
            --server $SqlServerName `
            --database $DatabaseName `
            --resource-group $ResourceGroup `
            --auth-type ADPassword `
            --file $sqlScriptPath 2>&1
        
        Write-Host "  ✓ Managed identity SQL user removed" -ForegroundColor Red
        Write-Host "  Impact: Application will fail to authenticate to SQL Database" -ForegroundColor DarkRed
    }
    catch {
        Write-Host "  ⚠ Could not execute SQL automatically" -ForegroundColor Yellow
        Write-Host "  Please manually execute in Azure Portal Query Editor:" -ForegroundColor Yellow
        Write-Host "  ---" -ForegroundColor DarkGray
        Write-Host "  DROP USER [$AppServiceName];" -ForegroundColor White
        Write-Host "  ---" -ForegroundColor DarkGray
    }
    finally {
        Remove-Item $sqlScriptPath -ErrorAction SilentlyContinue
    }
    
    Write-Host ""
    
    # Restart App Service to clear connection pool
    Write-Host "[3/3] Restarting App Service to clear connection pool..." -ForegroundColor Yellow
    Write-Host "  Note: This forces the app to attempt new connections" -ForegroundColor DarkGray
    az webapp restart --name $AppServiceName --resource-group $ResourceGroup 2>&1 | Out-Null
    Write-Host "  ✓ App Service restarted" -ForegroundColor Red
    Write-Host "  Impact: Existing pooled connections cleared, errors will be immediate" -ForegroundColor DarkRed
    Write-Host ""
    
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "  SYSTEM BROKEN!" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "Expected Symptoms:" -ForegroundColor Yellow
    Write-Host "  • /health/sql returns unhealthy" -ForegroundColor Gray
    Write-Host '  • Error: {"status":"unhealthy","error":"Login failed for user \".\"","errorType":"SqlException"}' -ForegroundColor Gray
    Write-Host "  • API endpoint returns 500 errors" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Root Causes Introduced:" -ForegroundColor Yellow
    Write-Host "  1. Private DNS Zone not linked to VNet → DNS resolution fails" -ForegroundColor Gray
    Write-Host "  2. Managed identity user not in SQL Database → AAD auth fails" -ForegroundColor Gray
    Write-Host "  3. Connection pool cleared → Errors are immediate (not intermittent)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Note: Wait 30-45 seconds for app to fully restart before testing" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Diagnose with:" -ForegroundColor Cyan
    Write-Host "  .\breakfix.ps1 -Action diagnose" -ForegroundColor White
    Write-Host ""
    Write-Host "Test with:" -ForegroundColor Cyan
    Write-Host "  curl https://$AppServiceName.azurewebsites.net/health/sql" -ForegroundColor White
    Write-Host ""
}

# Function to fix the system
function Invoke-Fix {
    Write-Host "🟢 FIXING THE SYSTEM..." -ForegroundColor Green
    Write-Host ""
    
    # Fix #1: Recreate Private DNS Zone VNet Link
    Write-Host "[1/2] Recreating Private DNS Zone VNet link..." -ForegroundColor Yellow
    
    # Get VNet ID
    $vnet = az network vnet show `
        --name $VNetName `
        --resource-group $ResourceGroup `
        --query id -o tsv
    
    if ([string]::IsNullOrEmpty($vnet)) {
        Write-Host "  ERROR: Could not find VNet: $VNetName" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "  VNet ID: $vnet" -ForegroundColor Gray
    
    # Create VNet link
    $linkName = "$VNetName-link"
    Write-Host "  Creating VNet link: $linkName" -ForegroundColor Gray
    
    az network private-dns link vnet create `
        --resource-group $ResourceGroup `
        --zone-name $privateDnsZoneName `
        --name $linkName `
        --virtual-network $vnet `
        --registration-enabled false 2>&1 | Out-Null
    
    Write-Host "  ✓ Private DNS Zone VNet link recreated" -ForegroundColor Green
    Write-Host ""
    
    # Fix #2: Recreate Managed Identity SQL User
    Write-Host "[2/2] Recreating managed identity in SQL Database..." -ForegroundColor Yellow
    
    # Get SQL Server FQDN
    $sqlServer = az sql server show --name $SqlServerName --resource-group $ResourceGroup | ConvertFrom-Json
    $sqlServerFqdn = $sqlServer.fullyQualifiedDomainName
    
    Write-Host "  Connecting to SQL Server: $sqlServerFqdn" -ForegroundColor Gray
    
    # Create SQL script to recreate user and grant permissions
    $createUserSql = @"
-- Create managed identity user if not exists
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = '$AppServiceName')
BEGIN
    CREATE USER [$AppServiceName] FROM EXTERNAL PROVIDER;
    PRINT 'User [$AppServiceName] created successfully';
END
ELSE
BEGIN
    PRINT 'User [$AppServiceName] already exists';
END
GO

-- Grant permissions
ALTER ROLE db_datareader ADD MEMBER [$AppServiceName];
ALTER ROLE db_datawriter ADD MEMBER [$AppServiceName];
ALTER ROLE db_ddladmin ADD MEMBER [$AppServiceName];
GO

PRINT 'Permissions granted successfully';
GO
"@
    
    $sqlScriptPath = Join-Path $env:TEMP "create_sql_user.sql"
    $createUserSql | Out-File -FilePath $sqlScriptPath -Encoding UTF8
    
    Write-Host "  Executing SQL commands to create user and grant permissions..." -ForegroundColor Gray
    Write-Host "  Note: This requires Azure AD authentication to SQL Server" -ForegroundColor DarkGray
    
    # Try to execute using Azure CLI
    try {
        $result = az sql db query `
            --server $SqlServerName `
            --database $DatabaseName `
            --resource-group $ResourceGroup `
            --auth-type ADPassword `
            --file $sqlScriptPath 2>&1
        
        Write-Host "  ✓ Managed identity SQL user recreated with permissions" -ForegroundColor Green
    }
    catch {
        Write-Host "  ⚠ Could not execute SQL automatically" -ForegroundColor Yellow
        Write-Host "  Please manually execute in Azure Portal Query Editor:" -ForegroundColor Yellow
        Write-Host "  ---" -ForegroundColor DarkGray
        Write-Host "  CREATE USER [$AppServiceName] FROM EXTERNAL PROVIDER;" -ForegroundColor White
        Write-Host "  ALTER ROLE db_datareader ADD MEMBER [$AppServiceName];" -ForegroundColor White
        Write-Host "  ALTER ROLE db_datawriter ADD MEMBER [$AppServiceName];" -ForegroundColor White
        Write-Host "  ALTER ROLE db_ddladmin ADD MEMBER [$AppServiceName];" -ForegroundColor White
        Write-Host "  GO" -ForegroundColor White
        Write-Host "  ---" -ForegroundColor DarkGray
    }
    finally {
        Remove-Item $sqlScriptPath -ErrorAction SilentlyContinue
    }
    
    Write-Host ""
    
    # Restart App Service to clear any cached connection issues
    Write-Host "[3/3] Restarting App Service to clear connection cache..." -ForegroundColor Yellow
    az webapp restart --name $AppServiceName --resource-group $ResourceGroup 2>&1 | Out-Null
    Write-Host "  ✓ App Service restarted" -ForegroundColor Green
    Write-Host ""
    
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  SYSTEM FIXED!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Wait 30 seconds for app to restart, then test:" -ForegroundColor Yellow
    Write-Host "  curl https://$AppServiceName.azurewebsites.net/health/sql" -ForegroundColor White
    Write-Host ""
    Write-Host "Expected Result:" -ForegroundColor Green
    Write-Host "  • status: healthy" -ForegroundColor Gray
    Write-Host "  • connectionState: Open" -ForegroundColor Gray
    Write-Host "  • database: $DatabaseName" -ForegroundColor Gray
    Write-Host ""
}

# Main execution
try {
    if ($Action -eq "diagnose") {
        Invoke-Diagnose
    }
    elseif ($Action -eq "break") {
        Invoke-Break
    }
    elseif ($Action -eq "fix") {
        Invoke-Fix
    }
}
catch {
    Write-Host ""
    Write-Host "ERROR: $_" -ForegroundColor Red
    Write-Host ""
    exit 1
}

Write-Host "Script completed successfully!" -ForegroundColor Cyan
Write-Host ""
