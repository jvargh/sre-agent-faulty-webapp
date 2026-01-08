# SQL Permissions Configuration Script
param(
    [string]$WebAppName = "app-y7njcffivri2q",
    [string]$SqlServer = "sql-y7njcffivri2q",
    [string]$DatabaseName = "FaultyWebAppDb"
)

$ErrorActionPreference = "Continue"

Write-Host "`n==== Configuring SQL Database Permissions ====" -ForegroundColor Magenta

# SQL commands to execute
$sqlCommands = @"
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = N'$WebAppName')
BEGIN
    CREATE USER [$WebAppName] FROM EXTERNAL PROVIDER;
    PRINT 'User created successfully';
END
ELSE
BEGIN
    PRINT 'User already exists';
END

ALTER ROLE db_datareader ADD MEMBER [$WebAppName];
ALTER ROLE db_datawriter ADD MEMBER [$WebAppName];
ALTER ROLE db_ddladmin ADD MEMBER [$WebAppName];

PRINT 'Permissions granted successfully';
"@

Write-Host "Web App: $WebAppName" -ForegroundColor Cyan
Write-Host "SQL Server: $SqlServer.database.windows.net" -ForegroundColor Cyan
Write-Host "Database: $DatabaseName" -ForegroundColor Cyan
Write-Host ""

# Save SQL commands to file
$sqlFile = "configure-permissions.sql"
$sqlCommands | Out-File -FilePath $sqlFile -Encoding UTF8

Write-Host "SQL commands saved to: $sqlFile" -ForegroundColor Green
Write-Host ""
Write-Host "Attempting to execute SQL commands..." -ForegroundColor Cyan

# Try multiple methods
$success = $false

# Method 1: Using az sql db query (requires Azure AD auth)
try {
    Write-Host "Method 1: Using Azure CLI SQL query..." -ForegroundColor Yellow
    $result = az sql db query `
        --server $SqlServer `
        --database $DatabaseName `
        --auth-type "ADIntegrated" `
        --query-file $sqlFile `
        2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ SQL permissions configured successfully!" -ForegroundColor Green
        $success = $true
    } else {
        Write-Host "Azure CLI method failed" -ForegroundColor Red
    }
} catch {
    Write-Host "Error with Azure CLI method: $_" -ForegroundColor Red
}

# If automated methods fail, provide manual instructions
if (-not $success) {
    Write-Host "`n⚠ Automated configuration failed. Please configure manually:" -ForegroundColor Yellow
    Write-Host "`nOption 1: Azure Portal Query Editor" -ForegroundColor Cyan
    Write-Host "=================================" -ForegroundColor Cyan
    Write-Host "1. Navigate to: https://portal.azure.com" -ForegroundColor White
    Write-Host "2. Go to: SQL databases -> $DatabaseName" -ForegroundColor White
    Write-Host "3. Click: Query editor (preview)" -ForegroundColor White
    Write-Host "4. Sign in with your Entra ID account" -ForegroundColor White
    Write-Host "5. Copy and run these commands:" -ForegroundColor White
    Write-Host ""
    Write-Host $sqlCommands -ForegroundColor Yellow
    Write-Host ""
    
    Write-Host "`nOption 2: Using Azure Data Studio or SSMS" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "Server: $SqlServer.database.windows.net" -ForegroundColor White
    Write-Host "Database: $DatabaseName" -ForegroundColor White
    Write-Host "Authentication: Azure Active Directory - Universal with MFA" -ForegroundColor White
    Write-Host "Then run the SQL commands from: $sqlFile" -ForegroundColor White
    Write-Host ""
    
    $response = Read-Host "Have you completed the SQL configuration? (Y/n)"
    if ($response -eq "" -or $response -eq "Y" -or $response -eq "y") {
        $success = $true
        Write-Host "✓ Proceeding with deployment" -ForegroundColor Green
    }
}

return $success
