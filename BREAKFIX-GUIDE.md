# Break/Fix Script for FaultyWebApp

This PowerShell script can deliberately introduce common errors and remediate them for testing and training purposes.

## Usage

### Diagnose the System
Check current system health and identify issues:
```powershell
.\breakfix.ps1 -Action diagnose
```

### Break the System
Introduces two critical errors:
```powershell
.\breakfix.ps1 -Action break
```

### Fix the System
Remediates all introduced errors:
```powershell
.\breakfix.ps1 -Action fix
```

### Custom Resource Names
```powershell
.\breakfix.ps1 -Action break `
    -ResourceGroup "your-rg" `
    -SqlServerName "your-sql-server" `
    -AppServiceName "your-app-service" `
    -VNetName "your-vnet" `
    -DatabaseName "your-database"
```

## Errors Introduced

### 1. Private DNS Zone Missing VNet Link
**Root Cause:** Removes the VNet link from the private DNS zone

**Impact:**
- SQL Server private endpoint DNS resolution fails
- Application cannot resolve private endpoint IP address
- Connection attempts fail with DNS errors

**Symptoms:**
- `/health/sql` returns unhealthy
- Error response: `{"status":"unhealthy","error":"Login failed for user \".\"","errorType":"SqlException"}`
- Error: "A network-related or instance-specific error occurred"
- DNS resolution failure in logs
- Connection string includes `Authentication=Active Directory Default`
- Azure SQL Server is Azure AD-only (`azureADOnlyAuthentication=true`)
- Public network access is Disabled

**Detection:**
```powershell
# Check VNet links
az network private-dns link vnet list `
    --resource-group sre-demo2-rg `
    --zone-name privatelink.database.windows.net
```

---

### 2. Managed Identity Not Created as SQL User
**Root Cause:** Removes the managed identity user from SQL Database

- Even when DNS resolves correctly, authentication fails

**Symptoms:**
- `/health/sql` returns unhealthy
- Error response: `{"status":"unhealthy","error":"Login failed for user 'app-y7njcffivri2q'","errorType":"SqlException"}`
- errorNumber: 18456 (Login failed)
- errorClass: 14 (Security error)
- No contained database user exists for the Web App's managed identity
- `/health/sql` returns unhealthy
- Error: "Login failed for user 'app-y7njcffivri2q'"
- errorType: "SqlException"
- errorNumber: 18456

**Detection:**
```powershell
# Check SQL Database health
curl https://app-y7njcffivri2q.azurewebsites.net/health/sql
```

## T0. Diagnose Current State
```powershell
# Check system health and identify any issues
.\breakfix.ps1 -Action diagnose
```

**Expected Output (Healthy System):**
```
[1/4] Checking Private DNS Zone VNet Link...
  ✓ VNet link exists: vnet-y7njcffivri2q-link (Succeeded)

[2/4] Checking App Service Configuration...
  ✓ Connection string configured
  ✓ Connection string includes 'Authentication=Active Directory Default'

[3/4] Checking SQL Database User...
  SQL Server: sql-y7njcffivri2q.database.windows.net
  Managed Identity: app-y7njcffivri2q

[4/4] Testing Health Endpoint...
  ✓ Health check PASSED
     Status: healthy
     Connection State: Open
     Database: FaultyWebAppDb

✅ No issues detected - System is healthy!
```

### esting Workflow
{"status":"unhealthy","error":"Login failed for user \".\"","errorType":"SqlException"}
  • API endpoint returns 500 errors

Root Causes Introduced:
  1. Private DNS Zone not linked to VNet → DNS resolution fails
  2. Managed identity user not in SQL Database → AAD auth fail
# Should return status: healthy
Invoke-RestMethod -Uri "https://app-y7njcffivri2q.azurewebsites.net/health/sql"
```

### 2. Break the System

# Or diagnose to see detailed analysis
.\breakfix.ps1 -Action diagnose
```

**Expected Response:**
```json
{
  "status": "unhealthy",
  "error": "Login failed for user 'app-y7njcffivri2q'",
  "errorType": "SqlException",
  "errorNumber": 18456,
  "errorClass": 14,
  "state": 1
}
```

**Diagnose Output (Broken System):**
```
[1/4] Checking Private DNS Zone VNet Link...
  ❌ ISSUE: No VNet links found in Private DNS Zone
     Impact: DNS resolution for private endpoint will fail

[2/4] Checking App Service Configuration...
  ✓ Connection string configured
  ✓ Connection string includes 'Authentication=Active Directory Default'

[3/4] Checking SQL Database User...
  SQL Server: sql-y7njcffivri2q.database.windows.net
  Managed Identity: app-y7njcffivri2q

[4/4] Testing Health Endpoint...
  ❌ Health check FAILED
     Status: unhealthy
     Error: Login failed for user 'app-y7njcffivri2q'
     Error Type: SqlException

  Root Cause Analysis:
     • Managed identity user not created in SQL Database
     • User 'app-y7njcffivri2q' does not have SQL permissions

⚠️  Issues Found: 2
  • Private DNS Zone VNet Link Missing
  • Managed Identity SQL User Missing ✓ Private DNS Zone VNet link removed
  Impact: SQL Server private endpoint DNS resolution will fail

[2/2] Removing managed identity from SQL Database...
  ✓ Managed identity SQL user removed
  Impact: Application will fail to authenticate to SQL Database

========================================
  SYSTEM BROKEN!
========================================

Expected Symptoms:
  • /health/sql returns unhealthy
  • Error: 'Login failed for user'
  • Error: DNS resolution failure
  • API returns 500 errors
```

### 3. Verify Errors
```powershell
# Should return unhealthy status with errors
Invoke-RestMethod -Uri "https://app-y7njcffivri2q.azurewebsites.net/health/sql"
```

**Expected Response:**
```json
{
  "status": "unhealthy",
  "error": "Login failed for user 'app-y7njcffivri2q'",
  "errorType": "SqlException",
  "errorNumber": 18456
}
```

### 4. Fix the System
```powershell
.\breakfix.ps1 -Action fix
```

**Expected Output:**
```
🟢 FIXING THE SYSTEM...

[1/2] Recreating Private DNS Zone VNet link...
  ✓ Private DNS Zone VNet link recreated

[2/2] Recreating managed identity in SQL Database...
  ✓ Managed identity SQL user recreated with permissions

[3/3] Restarting App Service to clear connection cache...
  ✓ App Service restarted

========================================
  SYSTEM FIXED!
========================================

Wait 30 seconds for app to restart, then test:
  curl https://app-y7njcffivri2q.azurewebsites.net/health/sql
```

### 5. Verify System is Healthy Again
```powershell
# Wait 30 seconds for app to restart
Start-Sleep -Seconds 30

# Should return status: healthy
Invoke-RestMethod -Uri "https://app-y7njcffivri2q.azurewebsites.net/health/sql"
```

**Expected Response:**
```json
{
  "status": "healthy",
  "message": "SQL connection successful",
  "connectionState": "Open",
  "database": "FaultyWebAppDb",
  "serverVersion": "16.0.0.0"
}
```

## Troubleshooting

### Manual SQL Commands (If Automatic Execution Fails)

**To Break (Drop User):**
1. Navigate to Azure Portal → SQL Databases → FaultyWebAppDb → Query editor
2. Sign in with Entra ID
3. Execute:
```sql
DROP USER [app-y7njcffivri2q];
GO
```

**To Fix (Recreate User):**
1. Navigate to Azure Portal → SQL Databases → FaultyWebAppDb → Query editor
2. Sign in with Entra ID
3. Execute:
```sql
CREATE USER [app-y7njcffivri2q] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [app-y7njcffivri2q];
ALTER ROLE db_datawriter ADD MEMBER [app-y7njcffivri2q];
ALTER ROLE db_ddladmin ADD MEMBER [app-y7njcffivri2q];
GO
```

## Use Cases

### Training and Education
- Demonstrate common Azure connectivity issues
- Practice troubleshooting with `/health/sql` diagnostics
- Learn about private endpoints and DNS resolution
- Understand managed identity authentication flow

### Testing Monitoring and Alerting
- Verify health check monitoring is working
- Test alerting on unhealthy status
- Validate incident response procedures
- Practice root cause analysis

### Chaos Engineering
- Test application resilience
- Verify graceful degradation
- Diagnose initial state
.\breakfix.ps1 -Action diagnose

# Break
.\breakfix.ps1 -Action break

# Verify broken
.\breakfix.ps1 -Action diagnose
curl https://app-y7njcffivri2q.azurewebsites.net/health/sql

# Fix
.\breakfix.ps1 -Action fix

# Wait and verify fixed
Start-Sleep 30
.\breakfix.ps1 -Action diagnosen restores original configuration
- No impact on application code or data

❌ **Do not use if:**
- In production environment without approval
- During business hours (if this is prod-like)
- Without understanding the impact
- Without ability to fix if something goes wrong

## ⚠️ Important: Connection Pooling Behavior

### Intermittent Failures After Breaking

**Symptom:** After running `.\breakfix.ps1 -Action break`, you may observe:
- `/health/sql` sometimes returns `"status":"healthy"`
- Web page intermittently shows "Error loading products" then successfully loads data
- System appears to work sporadically instead of failing consistently

**Root Cause:** 
.NET SQL connection pooling keeps existing database connections alive in memory. These pooled connections continue functioning even after:
- Private DNS Zone VNet link is removed
- SQL user credentials are deleted
- Network infrastructure is modified

**Why This Happens:**
1. Existing connections in the pool bypass new authentication/DNS resolution
2. When a pooled connection is reused → Request succeeds
3. When pool needs a new connection → Request fails
4. This creates intermittent, unpredictable behavior

**Solution:**
The break script automatically restarts the App Service (step 3/3) to:
- Clear all connection pools
- Force every request to establish new connections
- Ensure consistent failure behavior

**Wait Time Required:**
Allow **30-45 seconds** after the break script completes for:
- App Service to fully restart
- Connection pools to clear
- New connection attempts to fail consistently

### Testing Procedure
```powershell
# 1. Run break script (includes automatic restart)
.\breakfix.ps1 -Action break

# 2. Wait for app restart and pool clearing
Start-Sleep -Seconds 45

# 3. Test - should now consistently fail
curl https://app-y7njcffivri2q.azurewebsites.net/health/sql
```

**Expected Response (after restart):**
```json
{
  "status": "unhealthy",
  "error": "Connection was denied because Deny Public Network Access is set to Yes",
  "errorType": "SqlException",
  "errorNumber": 47073
}
```

If you still see "healthy" responses, manually restart:
```powershell
az webapp restart --name app-y7njcffivri2q --resource-group sre-demo2-rg
Start-Sleep -Seconds 45
```

## Requirements

- Azure CLI installed and authenticated
- PowerShell 5.1 or higher
- Permissions to modify:
  - Private DNS zones
  - SQL Database users (Entra ID admin)
  - App Service (for restart)

## Exit Codes

- `0` - Success
- `1` - Error occurred (check output for details)

## Examples

### Quick Break/Fix Cycle
```powershell
# Break
.\breakfix.ps1 -Action break

# Test
curl https://app-y7njcffivri2q.azurewebsites.net/health/sql

# Fix
.\breakfix.ps1 -Action fix

# Wait and test
Start-Sleep 30
curl https://app-y7njcffivri2q.azurewebsites.net/health/sql
```

### With Custom Resources
```powershell
$params = @{
    Action = "break"
    ResourceGroup = "my-rg"
    SqlServerName = "my-sql-server"
    AppServiceName = "my-app"
    VNetName = "my-vnet"
    DatabaseName = "my-db"
}

.\breakfix.ps1 @params
```

## Related Documentation

- [DEPLOYMENT-SUMMARY.md](DEPLOYMENT-SUMMARY.md) - Full deployment guide
- [README.md](README.md) - Project overview
- Azure Docs: [Private Endpoints](https://docs.microsoft.com/azure/private-link/private-endpoint-overview)
- Azure Docs: [Managed Identities](https://docs.microsoft.com/azure/active-directory/managed-identities-azure-resources/overview)
