# Bicep Infrastructure for FaultyWebApp

This directory contains the Bicep infrastructure as code (IaC) for deploying the FaultyWebApp to Azure with private networking and managed identity.

## Architecture

The infrastructure includes:

- **Virtual Network** with two subnets:
  - App Service VNet Integration subnet
  - SQL Server Private Endpoint subnet
- **Azure SQL Server** with:
  - Private endpoint (no public access)
  - Entra ID-only authentication
  - Private DNS zone for name resolution
- **App Service** with:
  - VNet integration for private SQL access
  - System-assigned managed identity
  - Health check endpoint
  - Connection string configured

## Prerequisites

1. **Azure Developer CLI (azd)**: [Install azd](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd)
2. **Azure CLI**: [Install az](https://learn.microsoft.com/cli/azure/install-azure-cli)
3. **Azure subscription** with sufficient permissions
4. **.NET 8 SDK**: For building the application

## Deployment Steps

### 1. Initialize azd environment

```bash
azd init
```

### 2. Set required environment variables

You need to configure the Entra ID admin for SQL Server:

```bash
# Get your current user's object ID
$objectId = az ad signed-in-user show --query id -o tsv
$principalName = az ad signed-in-user show --query userPrincipalName -o tsv

# Set environment variables
azd env set AZURE_SQL_ADMIN_OBJECT_ID $objectId
azd env set AZURE_SQL_ADMIN_PRINCIPAL_NAME $principalName
azd env set AZURE_LOCATION "eastus"
```

### 3. Provision and deploy

```bash
# Provision infrastructure and deploy application
azd up
```

Or run separately:

```bash
# Provision infrastructure only
azd provision

# Deploy application only
azd deploy
```

## Post-Deployment Configuration

After deployment, you need to grant the Web App's managed identity access to the SQL database:

### Option 1: Using Azure Portal

1. Navigate to Azure SQL Database in the portal
2. Open Query Editor and authenticate with your Entra ID account
3. Run these SQL commands:

```sql
CREATE USER [app-<resource-token>] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [app-<resource-token>];
ALTER ROLE db_datawriter ADD MEMBER [app-<resource-token>];
ALTER ROLE db_ddladmin ADD MEMBER [app-<resource-token>];
```

### Option 2: Using sqlcmd with Entra ID auth

```bash
# Get variables from azd
$webAppName = azd env get-value AZURE_WEBAPP_NAME
$sqlServer = azd env get-value AZURE_SQL_SERVER_NAME
$dbName = azd env get-value AZURE_SQL_DATABASE_NAME

# Get access token
$token = az account get-access-token --resource https://database.windows.net --query accessToken -o tsv

# Connect and run SQL commands
sqlcmd -S $sqlServer.database.windows.net -d $dbName -G -P $token -Q "
CREATE USER [$webAppName] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [$webAppName];
ALTER ROLE db_datawriter ADD MEMBER [$webAppName];
ALTER ROLE db_ddladmin ADD MEMBER [$webAppName];
"
```

## File Structure

```
infra/
├── main.bicep              # Main orchestration template
├── main.bicepparam         # Parameters file
├── abbreviations.json      # Azure resource naming abbreviations
└── modules/
    ├── network.bicep       # VNet, subnets, private DNS
    ├── sql.bicep           # SQL Server with private endpoint
    └── webapp.bicep        # App Service with VNet integration
```

## Key Features

### Security

- ✅ **No public SQL access**: SQL Server is only accessible via private endpoint
- ✅ **Entra ID only**: SQL authentication is disabled
- ✅ **Managed identity**: No connection string passwords
- ✅ **VNet integration**: App Service routes all traffic through VNet
- ✅ **HTTPS only**: App Service enforces HTTPS
- ✅ **TLS 1.2+**: Minimum TLS version enforced

### Networking

- Private endpoint for SQL Server
- Private DNS zone for name resolution
- VNet integration for App Service
- All database traffic stays on Azure backbone

## Useful Commands

```bash
# Check deployment status
azd show

# View environment variables
azd env get-values

# View logs
azd monitor

# Tear down all resources
azd down
```

## Customization

### Change App Service Plan SKU

Edit `infra/main.bicepparam`:
```bicep
param appServicePlanSku = 'S1'  // or 'P1v3', 'P2v3', etc.
```

### Change SQL Database SKU

Edit `infra/modules/sql.bicep`:
```bicep
sku: {
  name: 'S0'  // or 'S1', 'S2', 'P1', etc.
  tier: 'Standard'
}
```

### Add Application Insights

Add to `infra/modules/webapp.bicep`:
```bicep
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-${resourceToken}'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
  }
}
```

## Troubleshooting

### SQL Connection Failures

1. Verify VNet integration is active
2. Check private endpoint DNS resolution
3. Confirm managed identity has database permissions
4. Review App Service logs: `azd monitor`

### Deployment Failures

1. Check Azure subscription permissions
2. Verify all required environment variables are set
3. Review deployment logs in Azure Portal
4. Ensure resource names are globally unique

## Cost Estimation

Approximate monthly costs (East US):
- App Service Plan (P1v3): ~$150/month
- SQL Database (Basic): ~$5/month
- VNet & Private Endpoint: ~$10/month
- **Total**: ~$165/month

Use [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/) for accurate estimates.
