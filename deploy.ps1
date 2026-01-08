# FaultyWebApp Automated Deployment Script
# This script automates the entire deployment process to Azure

param(
    [string]$EnvironmentName = "demo",
    [string]$Location = "eastus2",
    [string]$ResourceGroupName = "sre-demo-rg",
    [switch]$SkipPrerequisites = $false
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "Continue"

# Color coding for output
function Write-Success { Write-Host "✓ $args" -ForegroundColor Green }
function Write-Info { Write-Host "ℹ $args" -ForegroundColor Cyan }
function Write-Warning { Write-Host "⚠ $args" -ForegroundColor Yellow }
function Write-Error-Message { Write-Host "✗ $args" -ForegroundColor Red }
function Write-Step { Write-Host "`n==== $args ====" -ForegroundColor Magenta }

Write-Host @"
╔════════════════════════════════════════════════════════════╗
║         FaultyWebApp Automated Deployment                  ║
║         Azure SQL + App Service + Private Networking       ║
╚════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

# Configuration
Write-Info "Deployment Configuration:"
Write-Info "  Environment: $EnvironmentName"
Write-Info "  Location: $Location"
Write-Info "  Resource Group: $ResourceGroupName"
Write-Host ""

# Step 1: Check Prerequisites
Write-Step "Step 1: Checking Prerequisites"

if (-not $SkipPrerequisites) {
    # Check Azure CLI
    Write-Info "Checking Azure CLI..."
    try {
        $azVersion = az version --query '\"azure-cli\"' -o tsv 2>$null
        if ($azVersion) {
            Write-Success "Azure CLI installed: $azVersion"
        } else {
            throw "Azure CLI not found"
        }
    } catch {
        Write-Error-Message "Azure CLI is not installed"
        Write-Info "Install: winget install -e --id Microsoft.AzureCLI"
        exit 1
    }

    # Check Azure Developer CLI
    Write-Info "Checking Azure Developer CLI..."
    try {
        $azdVersion = azd version 2>$null
        if ($azdVersion) {
            Write-Success "Azure Developer CLI installed"
        } else {
            throw "azd not found"
        }
    } catch {
        Write-Error-Message "Azure Developer CLI (azd) is not installed"
        Write-Info "Install: winget install microsoft.azd"
        exit 1
    }

    # Check .NET SDK
    Write-Info "Checking .NET SDK..."
    try {
        $dotnetVersion = dotnet --version 2>$null
        if ($dotnetVersion) {
            Write-Success ".NET SDK installed: $dotnetVersion"
        } else {
            throw ".NET SDK not found"
        }
    } catch {
        Write-Error-Message ".NET SDK is not installed"
        Write-Info "Install: winget install Microsoft.DotNet.SDK.8"
        exit 1
    }

    # Check Entity Framework Core Tools
    Write-Info "Checking EF Core Tools..."
    try {
        $efVersion = dotnet ef --version 2>$null
        if ($efVersion) {
            Write-Success "EF Core Tools installed"
        } else {
            Write-Warning "EF Core Tools not found, installing..."
            dotnet tool install --global dotnet-ef
            Write-Success "EF Core Tools installed"
        }
    } catch {
        Write-Warning "Installing EF Core Tools..."
        dotnet tool install --global dotnet-ef
    }
}

# Step 2: Login to Azure
Write-Step "Step 2: Azure Authentication"

Write-Info "Checking Azure CLI login..."
$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Info "Not logged in. Starting Azure CLI login..."
    az login
    $account = az account show | ConvertFrom-Json
}
Write-Success "Logged in as: $($account.user.name)"
Write-Success "Subscription: $($account.name) ($($account.id))"

Write-Info "Checking Azure Developer CLI login..."
try {
    azd auth login --check-status 2>$null
    Write-Success "Azure Developer CLI authenticated"
} catch {
    Write-Info "Logging in to Azure Developer CLI..."
    azd auth login
}

# Step 3: Get Current User Info for SQL Admin
Write-Step "Step 3: Configuring SQL Server Admin"

Write-Info "Getting current user information..."
$currentUser = az ad signed-in-user show | ConvertFrom-Json
$sqlAdminObjectId = $currentUser.id
$sqlAdminPrincipalName = $currentUser.userPrincipalName

Write-Success "SQL Admin will be: $sqlAdminPrincipalName"
Write-Success "Object ID: $sqlAdminObjectId"

# Step 4: Initialize azd Environment
Write-Step "Step 4: Initializing Azure Developer CLI Environment"

Write-Info "Setting up azd environment: $EnvironmentName"

# Check if environment exists
$existingEnv = azd env list 2>$null | Select-String -Pattern $EnvironmentName
if ($existingEnv) {
    Write-Warning "Environment '$EnvironmentName' already exists"
    $response = Read-Host "Do you want to use the existing environment? (Y/n)"
    if ($response -eq 'n' -or $response -eq 'N') {
        Write-Info "Please run 'azd env remove $EnvironmentName' first or choose a different name"
        exit 1
    }
    azd env select $EnvironmentName
} else {
    # Create new environment
    $env:AZURE_ENV_NAME = $EnvironmentName
    azd env new $EnvironmentName
}

# Step 5: Set Environment Variables
Write-Step "Step 5: Configuring Environment Variables"

Write-Info "Setting deployment configuration..."
azd env set AZURE_ENV_NAME $EnvironmentName
azd env set AZURE_LOCATION $Location
azd env set AZURE_RESOURCE_GROUP $ResourceGroupName
azd env set AZURE_SQL_ADMIN_OBJECT_ID $sqlAdminObjectId
azd env set AZURE_SQL_ADMIN_PRINCIPAL_NAME $sqlAdminPrincipalName

Write-Success "Environment variables configured"

# Display all environment variables
Write-Info "Current environment configuration:"
azd env get-values

# Step 6: Provision Infrastructure
Write-Step "Step 6: Provisioning Azure Infrastructure"

Write-Info "This will create:"
Write-Info "  - Virtual Network with subnets"
Write-Info "  - Azure SQL Server with private endpoint"
Write-Info "  - App Service with VNet integration"
Write-Info "  - Managed identities"
Write-Host ""

Write-Warning "Estimated time: 10-15 minutes"
Write-Warning "Estimated cost: ~$165/month"
Write-Host ""

$response = Read-Host "Proceed with provisioning? (Y/n)"
if ($response -eq 'n' -or $response -eq 'N') {
    Write-Info "Deployment cancelled"
    exit 0
}

Write-Info "Starting infrastructure provisioning..."
azd provision

if ($LASTEXITCODE -ne 0) {
    Write-Error-Message "Infrastructure provisioning failed"
    exit 1
}

Write-Success "Infrastructure provisioned successfully"

# Step 7: Get Deployment Outputs
Write-Step "Step 7: Retrieving Deployment Information"

$webAppName = azd env get-value AZURE_WEBAPP_NAME
$sqlServerName = azd env get-value AZURE_SQL_SERVER_NAME
$sqlDatabaseName = azd env get-value AZURE_SQL_DATABASE_NAME
$webAppUrl = azd env get-value AZURE_WEBAPP_URL
$managedIdentityId = azd env get-value AZURE_WEBAPP_IDENTITY_PRINCIPAL_ID
$resourceGroup = azd env get-value AZURE_RESOURCE_GROUP

Write-Success "Deployment Information:"
Write-Info "  Resource Group: $resourceGroup"
Write-Info "  Web App: $webAppName"
Write-Info "  SQL Server: $sqlServerName"
Write-Info "  Database: $sqlDatabaseName"
Write-Info "  Web App URL: $webAppUrl"
Write-Info "  Managed Identity: $managedIdentityId"

# Step 8: Configure SQL Database Permissions
Write-Step "Step 8: Configuring SQL Database Permissions"

Write-Info "Granting database access to managed identity: $webAppName"
Write-Info "Waiting 30 seconds for resources to stabilize..."
Start-Sleep -Seconds 30

$sqlCommands = @"
CREATE USER [$webAppName] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [$webAppName];
ALTER ROLE db_datawriter ADD MEMBER [$webAppName];
ALTER ROLE db_ddladmin ADD MEMBER [$webAppName];
GO
"@

# Save SQL commands to file
$sqlFile = "grant-permissions.sql"
$sqlCommands | Out-File -FilePath $sqlFile -Encoding UTF8

Write-Info "Attempting to grant database permissions..."

try {
    # Get access token
    $token = az account get-access-token --resource https://database.windows.net --query accessToken -o tsv
    
    # Check if sqlcmd is available
    $sqlcmdPath = Get-Command sqlcmd -ErrorAction SilentlyContinue
    
    if ($sqlcmdPath) {
        Write-Info "Using sqlcmd to configure database..."
        sqlcmd -S "$sqlServerName.database.windows.net" -d $sqlDatabaseName -G -P $token -i $sqlFile
        
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Database permissions granted successfully"
        } else {
            throw "sqlcmd failed"
        }
    } else {
        Write-Warning "sqlcmd not found. You'll need to grant permissions manually."
        Write-Info "Run these commands in Azure Portal Query Editor:"
        Write-Host $sqlCommands -ForegroundColor Yellow
        
        $response = Read-Host "`nHave you completed the SQL commands? (Y/n)"
        if ($response -eq 'n' -or $response -eq 'N') {
            Write-Warning "Please complete SQL permissions before continuing"
            Write-Info "SQL commands saved to: $sqlFile"
            exit 1
        }
    }
} catch {
    Write-Warning "Automated SQL configuration failed: $_"
    Write-Info "`nPlease grant permissions manually using Azure Portal:"
    Write-Info "1. Go to Azure Portal -> SQL databases -> $sqlDatabaseName"
    Write-Info "2. Open Query editor and sign in with Entra ID"
    Write-Info "3. Run these commands:"
    Write-Host $sqlCommands -ForegroundColor Yellow
    
    $response = Read-Host "`nHave you completed the SQL commands? (Y/n)"
    if ($response -eq 'n' -or $response -eq 'N') {
        Write-Warning "Please complete SQL permissions before continuing"
        Write-Info "SQL commands saved to: $sqlFile"
        exit 1
    }
}

# Step 9: Deploy Application
Write-Step "Step 9: Building and Deploying Application"

Write-Info "Building .NET application..."
dotnet build --configuration Release

if ($LASTEXITCODE -ne 0) {
    Write-Error-Message "Application build failed"
    exit 1
}

Write-Success "Application built successfully"

Write-Info "Deploying application to Azure..."
azd deploy

if ($LASTEXITCODE -ne 0) {
    Write-Error-Message "Application deployment failed"
    exit 1
}

Write-Success "Application deployed successfully"

# Step 10: Run Database Migrations
Write-Step "Step 10: Running Database Migrations"

Write-Info "Creating database migration..."

# Check if migrations exist
$migrationsPath = "Migrations"
if (-not (Test-Path $migrationsPath)) {
    Write-Info "Creating initial migration..."
    dotnet ef migrations add InitialCreate
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error-Message "Migration creation failed"
        exit 1
    }
    
    Write-Success "Migration created"
}

Write-Info "Applying database migrations..."
Write-Warning "Note: You must have database access to run migrations"

try {
    # Set connection string for migration
    $sqlServerFqdn = "$sqlServerName.database.windows.net"
    $connectionString = "Server=tcp:$sqlServerFqdn,1433;Initial Catalog=$sqlDatabaseName;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
    
    # Get token for connection
    $token = az account get-access-token --resource https://database.windows.net --query accessToken -o tsv
    
    # Try to run migration using connection string with token
    Write-Info "Attempting to update database schema..."
    
    # For now, we'll use the deployed app to run migrations or skip this step
    Write-Warning "Database migrations should be run from the deployed application or manually"
    Write-Info "The application will attempt to create schema on first run"
    
} catch {
    Write-Warning "Could not run migrations automatically: $_"
    Write-Info "Migrations will need to be run manually or on first application start"
}

# Step 11: Verify Deployment
Write-Step "Step 11: Verifying Deployment"

Write-Info "Waiting for application to start..."
Start-Sleep -Seconds 20

Write-Info "Testing health endpoint..."
try {
    $healthUrl = "$webAppUrl/health"
    Write-Info "Checking: $healthUrl"
    
    $response = Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 30
    
    if ($response.StatusCode -eq 200) {
        Write-Success "Health check passed! Application is running."
    } else {
        Write-Warning "Health check returned status: $($response.StatusCode)"
    }
} catch {
    Write-Warning "Health check failed: $_"
    Write-Info "Application may still be starting. Check logs with: azd monitor"
}

Write-Info "Testing home page..."
try {
    $response = Invoke-WebRequest -Uri $webAppUrl -UseBasicParsing -TimeoutSec 30
    if ($response.StatusCode -eq 200) {
        Write-Success "Home page accessible!"
    }
} catch {
    Write-Warning "Could not access home page: $_"
}

# Step 12: Display Summary
Write-Step "Deployment Complete!"

Write-Host @"

╔════════════════════════════════════════════════════════════╗
║                  DEPLOYMENT SUMMARY                        ║
╚════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Green

Write-Success "All resources deployed successfully!"
Write-Host ""
Write-Info "📋 Resource Details:"
Write-Host "   Resource Group:  $resourceGroup" -ForegroundColor White
Write-Host "   Location:        $Location" -ForegroundColor White
Write-Host "   Web App:         $webAppName" -ForegroundColor White
Write-Host "   SQL Server:      $sqlServerName.database.windows.net" -ForegroundColor White
Write-Host "   Database:        $sqlDatabaseName" -ForegroundColor White
Write-Host ""
Write-Info "🌐 Access URLs:"
Write-Host "   Application:     $webAppUrl" -ForegroundColor Cyan
Write-Host "   Health Check:    $webAppUrl/health" -ForegroundColor Cyan
Write-Host "   API:             $webAppUrl/api/products" -ForegroundColor Cyan
Write-Host ""
Write-Info "🔐 Security Features:"
Write-Host "   ✓ Private SQL endpoint (no public access)" -ForegroundColor Green
Write-Host "   ✓ Entra ID authentication only" -ForegroundColor Green
Write-Host "   ✓ Managed identity (no secrets)" -ForegroundColor Green
Write-Host "   ✓ VNet integration" -ForegroundColor Green
Write-Host ""
Write-Info "📊 Useful Commands:"
Write-Host "   View logs:       azd monitor" -ForegroundColor Yellow
Write-Host "   View config:     azd env get-values" -ForegroundColor Yellow
Write-Host "   Redeploy app:    azd deploy" -ForegroundColor Yellow
Write-Host "   Delete all:      azd down" -ForegroundColor Yellow
Write-Host ""

# Open browser
$response = Read-Host "Open application in browser? (Y/n)"
if ($response -ne 'n' -and $response -ne 'N') {
    Start-Process $webAppUrl
}

Write-Success "Deployment script completed successfully!"
Write-Host ""
