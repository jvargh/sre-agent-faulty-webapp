# Sev1 Alert Runbook - FaultyWebApp

**Application:** FaultyWebApp  
**Resource Group:** sre-demo2-rg  
**Subscription ID:** 463a82d4-1896-4332-aeeb-618ee5a5aa93  
**Last Updated:** January 11, 2026

## Critical (Sev1) Alerts

### 1. SQL-Health-Endpoint-Unavailable-MultiRegion
- **Alert Name:** SQL-Health-Endpoint-Unavailable-MultiRegion-y7njcffivri2q
- **Severity:** Critical (Sev1)
- **Trigger Condition:** Health endpoint fails in 2+ Azure regions
- **Impact:** SQL database connectivity issues, service degradation or outage

### 2. SQL-Database-Connection-Unhealthy
- **Alert Name:** SQL-Database-Connection-Unhealthy-y7njcffivri2q
- **Severity:** Critical (Sev1)
- **Trigger Condition:** Application cannot connect to SQL database
- **Impact:** Complete service outage, data access failure

---

## Resource Information

```yaml
Web App:
  Name: app-y7njcffivri2q
  Resource ID: /subscriptions/463a82d4-1896-4332-aeeb-618ee5a5aa93/resourceGroups/sre-demo2-rg/providers/Microsoft.Web/sites/app-y7njcffivri2q
  URL: https://app-y7njcffivri2q.azurewebsites.net
  Health Endpoints:
    - https://app-y7njcffivri2q.azurewebsites.net/health
    - https://app-y7njcffivri2q.azurewebsites.net/health/sql

SQL Database:
  Server: sql-y7njcffivri2q.database.windows.net
  Database: FaultyWebAppDb
  Authentication: Entra ID (Managed Identity)
  Connection: Private Endpoint Only

Application Insights:
  Name: appi-y7njcffivri2q
  App ID: 22e37f3e-265c-4b6a-b465-9c0f89289c2e
  Resource ID: /subscriptions/463a82d4-1896-4332-aeeb-618ee5a5aa93/resourceGroups/sre-demo2-rg/providers/microsoft.insights/components/appi-y7njcffivri2q

Networking:
  VNet: vnet-y7njcffivri2q
  Private DNS Zone: privatelink.database.windows.net
  Managed Identity Principal ID: ba1fa75f-e38e-479a-8e86-5f0dc2561904
```

---

## PART 1: MONITORING & DETECTION

### 1.1 Alert Notification Channels
Alerts are sent to:
- Action Group: `ag-health-y7njcffivri2q`
- Role: Monitoring Contributors (Azure RBAC)
- Portal: Azure Monitor Alerts

### 1.2 Verify Alert Status

**Check Active Alerts:**
```powershell
az monitor metrics alert show `
  --name SQL-Health-Endpoint-Unavailable-MultiRegion-y7njcffivri2q `
  --resource-group sre-demo2-rg `
  --query "{Name:name, Enabled:properties.enabled, Condition:properties.criteria}" `
  -o json
```

**View All Fired Alerts:**
```powershell
# Get all alerts that have fired in last 24 hours
az monitor metrics alert list `
  --resource-group sre-demo2-rg `
  --query "[?properties.enabled==\`true\`].{Name:name, Severity:properties.severity, LastEvaluated:properties.lastUpdatedTime}" `
  -o table

# Check specific alert history in Activity Log
az monitor activity-log list `
  --resource-group sre-demo2-rg `
  --start-time (Get-Date).AddHours(-1).ToString('yyyy-MM-ddTHH:mm:ssZ') `
  --query "[?contains(operationName.value, 'Microsoft.Insights/metricAlerts')].{Time:eventTimestamp, Alert:resourceId, Status:status.value}" `
  -o table
```

### 1.3 Confirm Issue via Health Endpoints

**Test Health Endpoint Directly:**
```powershell
# General health check
Invoke-RestMethod -Uri https://app-y7njcffivri2q.azurewebsites.net/health

# SQL health check (detailed)
Invoke-RestMethod -Uri https://app-y7njcffivri2q.azurewebsites.net/health/sql
```

**Expected Healthy Response:**
```json
{
  "status": "healthy",
  "message": "SQL connection successful",
  "connectionState": "Open",
  "database": "FaultyWebAppDb",
  "serverVersion": "12.00.0924"
}
```

**Expected Unhealthy Response (Sev1):**
```json
{
  "status": "unhealthy",
  "error": "Connection was denied because Deny Public Network Access is set to Yes",
  "errorType": "SqlException",
  "errorNumber": 47073,
  "errorClass": 14,
  "state": 1
}
```

### 1.4 Check Application Insights Live Metrics

**Portal Link:**
```
https://portal.azure.com/#resource/subscriptions/463a82d4-1896-4332-aeeb-618ee5a5aa93/resourceGroups/sre-demo2-rg/providers/Microsoft.Insights/components/appi-y7njcffivri2q/livemetrics
```

**What to Check:**
- Request rate (should be > 0 if app is accessible)
- Failed requests (sudden spike indicates issue)
- Dependency failures (SQL connection failures)
- Exception rate

### 1.5 Query Recent Failures

**Get Last 10 Failed Requests:**
```kusto
requests
| where timestamp > ago(15m)
| where success == false
| project timestamp, name, url, resultCode, duration
| order by timestamp desc
| take 10
```

**Get SQL Dependency Failures:**
```kusto
dependencies
| where timestamp > ago(15m)
| where type == "SQL"
| where success == false
| project timestamp, target, data, resultCode, duration
| order by timestamp desc
| take 10
```

---

## PART 2: MITIGATION STEPS

### 2.1 Immediate Response (First 5 Minutes)

**Priority:** Restore service as quickly as possible.

#### Step 1: Verify Service Status

```powershell
# Check if web app is running
az webapp show `
  --name app-y7njcffivri2q `
  --resource-group sre-demo2-rg `
  --query "{Name:name, State:state, AvailabilityState:availabilityState, LastModified:lastModifiedTimeUtc}" `
  -o table
```

#### Step 2: Test Health Endpoints

```powershell
# Test general health
$healthResponse = Invoke-RestMethod -Uri "https://app-y7njcffivri2q.azurewebsites.net/health" -ErrorAction SilentlyContinue
$healthResponse | ConvertTo-Json

# Test SQL health (detailed)
$sqlHealthResponse = Invoke-RestMethod -Uri "https://app-y7njcffivri2q.azurewebsites.net/health/sql" -ErrorAction SilentlyContinue
$sqlHealthResponse | ConvertTo-Json

# Analyze response
if ($sqlHealthResponse.status -eq "unhealthy") {
    Write-Host "❌ SQL Health Check FAILED" -ForegroundColor Red
    Write-Host "Error Number: $($sqlHealthResponse.errorNumber)" -ForegroundColor Yellow
    Write-Host "Error Type: $($sqlHealthResponse.errorType)" -ForegroundColor Yellow
    Write-Host "Error Message: $($sqlHealthResponse.error)" -ForegroundColor Yellow
    
    # Determine root cause based on error
    switch ($sqlHealthResponse.errorNumber) {
        47073 { 
            Write-Host "Root Cause: Private endpoint connectivity issue (Error 47073)" -ForegroundColor Cyan
            Write-Host "Action: Check VNet link and private DNS configuration" -ForegroundColor Cyan
        }
        18456 { 
            Write-Host "Root Cause: Authentication failure (Error 18456)" -ForegroundColor Cyan
            Write-Host "Action: Check managed identity SQL user permissions" -ForegroundColor Cyan
        }
        default {
            Write-Host "Root Cause: Unknown SQL error" -ForegroundColor Cyan
            Write-Host "Action: Review error message and query Application Insights" -ForegroundColor Cyan
        }
    }
}
```

#### Step 3: Check Infrastructure Components

```powershell
# 1. Check VNet Link Status
Write-Host "`n[1/4] Checking Private DNS Zone VNet Link..." -ForegroundColor Yellow
$vnetLinks = az network private-dns link vnet list `
  --resource-group sre-demo2-rg `
  --zone-name privatelink.database.windows.net `
  --query "[].{Name:name, State:provisioningState, VNet:virtualNetwork.id}" `
  -o json | ConvertFrom-Json

if ($vnetLinks.Count -eq 0) {
    Write-Host "  ❌ ISSUE: No VNet links found" -ForegroundColor Red
    Write-Host "  Impact: DNS resolution for private endpoint will fail" -ForegroundColor Red
} else {
    Write-Host "  ✓ VNet link exists: $($vnetLinks[0].Name) ($($vnetLinks[0].State))" -ForegroundColor Green
}

# 2. Check Private Endpoint Status
Write-Host "`n[2/4] Checking Private Endpoint..." -ForegroundColor Yellow
$privateEndpoint = az network private-endpoint list `
  --resource-group sre-demo2-rg `
  --query "[?contains(name, 'sql')].{Name:name, State:provisioningState, PrivateIP:customDnsConfigs[0].ipAddresses[0]}" `
  -o json | ConvertFrom-Json

if ($privateEndpoint) {
    Write-Host "  ✓ Private endpoint: $($privateEndpoint[0].Name)" -ForegroundColor Green
    Write-Host "  ✓ Private IP: $($privateEndpoint[0].PrivateIP)" -ForegroundColor Green
    Write-Host "  ✓ State: $($privateEndpoint[0].State)" -ForegroundColor Green
} else {
    Write-Host "  ❌ No private endpoint found" -ForegroundColor Red
}

# 3. Check App Service Configuration
Write-Host "`n[3/4] Checking App Service Configuration..." -ForegroundColor Yellow
$connectionString = az webapp config connection-string list `
  --name app-y7njcffivri2q `
  --resource-group sre-demo2-rg `
  --query "DefaultConnection.value" `
  -o tsv

if ($connectionString) {
    Write-Host "  ✓ Connection string configured" -ForegroundColor Green
    if ($connectionString -like "*Authentication=Active Directory Default*") {
        Write-Host "  ✓ Using Entra ID authentication (Managed Identity)" -ForegroundColor Green
    }
} else {
    Write-Host "  ℹ Connection string loaded from appsettings.json" -ForegroundColor Cyan
}

# 4. Check Managed Identity
Write-Host "`n[4/4] Checking Managed Identity..." -ForegroundColor Yellow
$identity = az webapp identity show `
  --name app-y7njcffivri2q `
  --resource-group sre-demo2-rg `
  --query "{PrincipalId:principalId, Type:type}" `
  -o json | ConvertFrom-Json

if ($identity.PrincipalId) {
    Write-Host "  ✓ Managed Identity enabled" -ForegroundColor Green
    Write-Host "  ✓ Principal ID: $($identity.PrincipalId)" -ForegroundColor Green
} else {
    Write-Host "  ❌ Managed Identity not configured" -ForegroundColor Red
}
```

### 2.2 Root Cause-Specific Mitigation

#### 2.2.1 Root Cause #1: Private DNS Zone VNet Link Missing

**Symptoms:**
- Error 47073: "Connection was denied because Deny Public Network Access is set to Yes"
- DNS resolution failure for privatelink.database.windows.net
- Cannot reach private endpoint (sql-y7njcffivri2q.database.windows.net)

**Resolution Time:** ~2 minutes

**Mitigation Steps:**

```powershell
# Step 1: Get VNet ID
Write-Host "Getting VNet details..." -ForegroundColor Yellow
$vnetId = az network vnet show `
  --resource-group sre-demo2-rg `
  --name vnet-y7njcffivri2q `
  --query "id" `
  -o tsv

Write-Host "VNet ID: $vnetId" -ForegroundColor Cyan

# Step 2: Verify link is missing (should show empty or error)
Write-Host "`nVerifying current state..." -ForegroundColor Yellow
az network private-dns link vnet list `
  --resource-group sre-demo2-rg `
  --zone-name privatelink.database.windows.net `
  --query "[].{Name:name, State:provisioningState, VNet:virtualNetwork.id}" `
  -o table

# Step 3: Create VNet link
Write-Host "`nCreating VNet link..." -ForegroundColor Yellow
az network private-dns link vnet create `
  --resource-group sre-demo2-rg `
  --zone-name privatelink.database.windows.net `
  --name vnet-y7njcffivri2q-link `
  --virtual-network $vnetId `
  --registration-enabled false

Write-Host "✓ VNet link created" -ForegroundColor Green

# Step 4: Verify link creation
Write-Host "`nVerifying VNet link status..." -ForegroundColor Yellow
az network private-dns link vnet show `
  --resource-group sre-demo2-rg `
  --zone-name privatelink.database.windows.net `
  --name vnet-y7njcffivri2q-link `
  --query "{Name:name, State:provisioningState, RegistrationEnabled:registrationEnabled}" `
  -o table

# Step 5: Wait for DNS propagation
Write-Host "`nWaiting 30 seconds for DNS propagation..." -ForegroundColor Yellow
Start-Sleep -Seconds 30

# Step 6: Restart App Service to clear connection pool
Write-Host "`nRestarting App Service..." -ForegroundColor Yellow
az webapp restart --name app-y7njcffivri2q --resource-group sre-demo2-rg
Write-Host "✓ Restart initiated" -ForegroundColor Green

# Step 7: Wait for app startup
Write-Host "`nWaiting 45 seconds for application startup..." -ForegroundColor Yellow
Start-Sleep -Seconds 45

Write-Host "`n✓ Mitigation complete - Proceed to verification (section 2.3)" -ForegroundColor Green
```

#### 2.2.2 Root Cause #2: Managed Identity SQL User Missing

**Symptoms:**
- Error: "Login failed for user '.'"
- Error 18456: Authentication failure
- errorType: "SqlException"
- Health endpoint shows unhealthy with login error

**Resolution Time:** ~3 minutes

**Mitigation Steps:**

```powershell
# Step 1: Get managed identity details
Write-Host "Getting managed identity details..." -ForegroundColor Yellow
$identity = az webapp identity show `
  --name app-y7njcffivri2q `
  --resource-group sre-demo2-rg `
  --query "{PrincipalId:principalId, TenantId:tenantId, Type:type}" `
  -o json | ConvertFrom-Json

Write-Host "Managed Identity Principal ID: $($identity.PrincipalId)" -ForegroundColor Cyan
Write-Host "Tenant ID: $($identity.TenantId)" -ForegroundColor Cyan

# Step 2: Prepare SQL commands
$sqlCommands = @"
-- Create managed identity user in database
CREATE USER [app-y7njcffivri2q] FROM EXTERNAL PROVIDER;

-- Grant necessary permissions
ALTER ROLE db_datareader ADD MEMBER [app-y7njcffivri2q];
ALTER ROLE db_datawriter ADD MEMBER [app-y7njcffivri2q];
ALTER ROLE db_ddladmin ADD MEMBER [app-y7njcffivri2q];

-- Verify user creation
SELECT name, type_desc, authentication_type_desc 
FROM sys.database_principals 
WHERE name = 'app-y7njcffivri2q';
"@

Write-Host "`nSQL Commands to execute:" -ForegroundColor Yellow
Write-Host $sqlCommands -ForegroundColor White

# Step 3: Execute SQL commands
Write-Host "`n⚠ MANUAL ACTION REQUIRED:" -ForegroundColor Red
Write-Host "Execute the above SQL commands using ONE of these methods:" -ForegroundColor Yellow
Write-Host ""
Write-Host "Option 1 - Azure Portal Query Editor:" -ForegroundColor Cyan
Write-Host "  1. Navigate to: https://portal.azure.com/#resource/subscriptions/463a82d4-1896-4332-aeeb-618ee5a5aa93/resourceGroups/sre-demo2-rg/providers/Microsoft.Sql/servers/sql-y7njcffivri2q/databases/FaultyWebAppDb/queryEditor"
Write-Host "  2. Authenticate using Entra ID (your admin account)"
Write-Host "  3. Paste and execute the SQL commands above"
Write-Host ""
Write-Host "Option 2 - Azure Data Studio or SSMS:" -ForegroundColor Cyan
Write-Host "  1. Connect to: sql-y7njcffivri2q.database.windows.net"
Write-Host "  2. Database: FaultyWebAppDb"
Write-Host "  3. Authentication: Azure Active Directory"
Write-Host "  4. Execute the SQL commands above"
Write-Host ""
Write-Host "Option 3 - Azure CLI with Invoke-Sqlcmd:" -ForegroundColor Cyan
Write-Host "  az sql db invoke-sqlcmd \"
Write-Host "    --server sql-y7njcffivri2q \"
Write-Host "    --database FaultyWebAppDb \"
Write-Host "    --query `"`$sqlCommands`" \"
Write-Host "    --use-entra-auth"
Write-Host ""

Read-Host "Press Enter after executing SQL commands"

# Step 4: Restart App Service to clear connection pool
Write-Host "`nRestarting App Service..." -ForegroundColor Yellow
az webapp restart --name app-y7njcffivri2q --resource-group sre-demo2-rg
Write-Host "✓ Restart initiated" -ForegroundColor Green

# Step 5: Wait for app startup
Write-Host "`nWaiting 45 seconds for application startup..." -ForegroundColor Yellow
Start-Sleep -Seconds 45

Write-Host "`n✓ Mitigation complete - Proceed to verification (section 2.3)" -ForegroundColor Green
```

### 2.3 Verification After Mitigation

**Run Full Verification:**

```powershell
Write-Host "`n=== POST-MITIGATION VERIFICATION ===" -ForegroundColor Cyan

# 1. Test health endpoints
Write-Host "`n[1/5] Testing Health Endpoints..." -ForegroundColor Yellow
try {
    $generalHealth = Invoke-RestMethod -Uri "https://app-y7njcffivri2q.azurewebsites.net/health"
    Write-Host "  ✓ General Health: $($generalHealth.status)" -ForegroundColor Green
} catch {
    Write-Host "  ❌ General Health: Failed - $($_.Exception.Message)" -ForegroundColor Red
}

try {
    $sqlHealth = Invoke-RestMethod -Uri "https://app-y7njcffivri2q.azurewebsites.net/health/sql"
    if ($sqlHealth.status -eq "healthy") {
        Write-Host "  ✓ SQL Health: $($sqlHealth.status)" -ForegroundColor Green
        Write-Host "    - Connection State: $($sqlHealth.connectionState)" -ForegroundColor Green
        Write-Host "    - Database: $($sqlHealth.database)" -ForegroundColor Green
        Write-Host "    - Server Version: $($sqlHealth.serverVersion)" -ForegroundColor Green
    } else {
        Write-Host "  ❌ SQL Health: $($sqlHealth.status)" -ForegroundColor Red
        Write-Host "    - Error: $($sqlHealth.error)" -ForegroundColor Red
        Write-Host "    - Error Number: $($sqlHealth.errorNumber)" -ForegroundColor Red
    }
} catch {
    Write-Host "  ❌ SQL Health: Failed - $($_.Exception.Message)" -ForegroundColor Red
}

# 2. Verify VNet link
Write-Host "`n[2/5] Verifying VNet Link..." -ForegroundColor Yellow
$vnetLink = az network private-dns link vnet show `
  --resource-group sre-demo2-rg `
  --zone-name privatelink.database.windows.net `
  --name vnet-y7njcffivri2q-link `
  --query "{Name:name, State:provisioningState, RegistrationEnabled:registrationEnabled}" `
  -o json 2>$null | ConvertFrom-Json

if ($vnetLink) {
    Write-Host "  ✓ VNet link exists: $($vnetLink.Name)" -ForegroundColor Green
    Write-Host "    - State: $($vnetLink.State)" -ForegroundColor Green
} else {
    Write-Host "  ❌ VNet link not found" -ForegroundColor Red
}

# 3. Verify Managed Identity
Write-Host "`n[3/5] Verifying Managed Identity..." -ForegroundColor Yellow
$identity = az webapp identity show `
  --name app-y7njcffivri2q `
  --resource-group sre-demo2-rg `
  --query "{PrincipalId:principalId, Type:type}" `
  -o json | ConvertFrom-Json

if ($identity.PrincipalId) {
    Write-Host "  ✓ Managed Identity: $($identity.Type)" -ForegroundColor Green
    Write-Host "    - Principal ID: $($identity.PrincipalId)" -ForegroundColor Green
} else {
    Write-Host "  ❌ Managed Identity not configured" -ForegroundColor Red
}

# 4. Check Application Insights recent requests
Write-Host "`n[4/5] Checking Application Insights..." -ForegroundColor Yellow
$recentRequests = az monitor app-insights query `
  --app appi-y7njcffivri2q `
  --resource-group sre-demo2-rg `
  --analytics-query "requests | where timestamp > ago(5m) | where name contains 'health' | project timestamp, name, success, resultCode, duration | order by timestamp desc | take 10" `
  -o json | ConvertFrom-Json

if ($recentRequests.tables[0].rows.Count -gt 0) {
    Write-Host "  ✓ Recent health check requests found" -ForegroundColor Green
    $successCount = ($recentRequests.tables[0].rows | Where-Object { $_[2] -eq $true }).Count
    $totalCount = $recentRequests.tables[0].rows.Count
    Write-Host "    - Success rate: $successCount/$totalCount" -ForegroundColor Green
} else {
    Write-Host "  ℹ No recent requests in Application Insights (may take 2-3 minutes)" -ForegroundColor Cyan
}

# 5. Check alert status
Write-Host "`n[5/5] Checking Alert Status..." -ForegroundColor Yellow
$criticalAlerts = az monitor metrics alert list `
  --resource-group sre-demo2-rg `
  --query "[?severity=='1' || severity=='2'].{Name:name, Enabled:enabled, Condition:criteria.allOf[0].name}" `
  -o json | ConvertFrom-Json

$activeAlerts = 0
foreach ($alert in $criticalAlerts) {
    if ($alert.Enabled) {
        $activeAlerts++
    }
}
Write-Host "  ✓ Monitoring alerts enabled: $activeAlerts" -ForegroundColor Green

Write-Host "`n=== VERIFICATION COMPLETE ===" -ForegroundColor Cyan
```

**Success Criteria:**
- ✅ Health endpoint returns `"status":"healthy"`
- ✅ Connection state shows `"Open"`
- ✅ Database name shows `"FaultyWebAppDb"`
- ✅ VNet link shows `"Succeeded"` state
- ✅ Managed Identity is configured with valid Principal ID
- ✅ Application Insights receiving requests (may take 2-3 minutes)
- ✅ All critical alerts are enabled

**If Verification Fails:**
- Wait additional 2-3 minutes for telemetry propagation
- Re-run health endpoint tests
- Check Application Insights Live Metrics in Azure Portal
- Review App Service logs: `az webapp log tail --name app-y7njcffivri2q --resource-group sre-demo2-rg`

### 2.4 Communication Template

**Initial Alert (Within 5 minutes):**
```
Subject: [SEV1] FaultyWebApp - SQL Database Connectivity Issue

Status: INVESTIGATING
Time Detected: [TIMESTAMP]
Impact: Users experiencing [service unavailable / degraded performance]
Alert: SQL-Health-Endpoint-Unavailable-MultiRegion
Root Cause: Under investigation

Actions Taken:
- Alert confirmed via health endpoint
- Diagnostic script executed
- Investigation in progress

Next Update: In 15 minutes or upon resolution
```

**Resolution Update:**
```
Subject: [SEV1] [RESOLVED] FaultyWebApp - SQL Database Connectivity Issue

Status: RESOLVED
Resolution Time: [TIMESTAMP] (Duration: X minutes)
Root Cause: [Private DNS Zone VNet link missing / Managed identity SQL user missing]
Impact: Service restored, all health checks passing

Actions Taken:
- [Recreated VNet link / Recreated SQL user]
- Restarted App Service
- Verified health endpoints
- Confirmed via Application Insights

RCA Document: [Link to follow]
```

---

## PART 3: ROOT CAUSE ANALYSIS (RCA)

### 3.1 Data Collection

**Time Window:** Collect data from 30 minutes before alert to present.

#### 3.1.1 Application Insights Logs

```kusto
// All requests during incident
requests
| where timestamp between(datetime([START_TIME]) .. datetime([END_TIME]))
| summarize 
    TotalRequests=count(),
    FailedRequests=countif(success==false),
    FailureRate=countif(success==false)*100.0/count(),
    AvgDuration=avg(duration)
  by bin(timestamp, 1m)
| order by timestamp asc

// SQL dependency failures
dependencies
| where timestamp between(datetime([START_TIME]) .. datetime([END_TIME]))
| where type == "SQL"
| where success == false
| project timestamp, target, data, resultCode, duration, customDimensions
| order by timestamp asc

// Exceptions during incident
exceptions
| where timestamp between(datetime([START_TIME]) .. datetime([END_TIME]))
| project timestamp, type, outerMessage, innermostMessage, operation_Name
| order by timestamp asc
```

#### 3.1.2 Azure Activity Logs

```powershell
# Get activity logs during incident
az monitor activity-log list `
  --resource-group sre-demo2-rg `
  --start-time [START_TIME] `
  --end-time [END_TIME] `
  --query "[?contains(resourceId, 'app-y7njcffivri2q') || contains(resourceId, 'sql-y7njcffivri2q') || contains(resourceId, 'privatelink.database.windows.net')].{Time:eventTimestamp, Operation:operationName.value, Status:status.value, Caller:caller}" `
  -o table
```

#### 3.1.3 Configuration Changes

```powershell
# Check recent deployments
az webapp deployment list `
  --name app-y7njcffivri2q `
  --resource-group sre-demo2-rg `
  --query "[].{Time:received_time, Status:status, Message:message}"

# Check VNet link changes
az network private-dns link vnet list `
  --resource-group sre-demo2-rg `
  --zone-name privatelink.database.windows.net `
  --query "[].{Name:name, State:provisioningState, LastModified:etag}"

# Check SQL user permissions
# (Manual: Connect to SQL via Azure Portal Query Editor)
# SELECT dp.name, dp.type_desc, dp.create_date
# FROM sys.database_principals dp
# WHERE dp.name = 'app-y7njcffivri2q';
```

#### 3.1.4 Alert History

```powershell
# Get alert firing history
az monitor metrics alert show `
  --name SQL-Health-Endpoint-Unavailable-MultiRegion-y7njcffivri2q `
  --resource-group sre-demo2-rg `
  --query "properties.{Description:description, LastEvaluated:lastUpdated, WindowSize:windowSize}"
```

### 3.2 Timeline Creation

**RCA Timeline Template:**

```markdown
## Incident Timeline

| Time (UTC) | Event | Source | Evidence |
|------------|-------|--------|----------|
| [TIME] | Alert triggered | Azure Monitor | Alert notification received |
| [TIME] | Investigation started | On-call engineer | Diagnostic script executed |
| [TIME] | Root cause identified | Diagnostic output | [VNet link missing / SQL user missing] |
| [TIME] | Mitigation started | Engineer | [Fix script executed / Manual commands] |
| [TIME] | Service restored | Health endpoint | Status returned to healthy |
| [TIME] | Verification complete | Application Insights | Success rate returned to 100% |
| [TIME] | Incident closed | On-call engineer | RCA document created |

**Total Duration:** X minutes
**Mean Time to Detect (MTTD):** X minutes
**Mean Time to Resolve (MTTR):** X minutes
```

### 3.3 Root Cause Categories

#### Category 1: Infrastructure Change
- **Cause:** Manual deletion or infrastructure drift
- **Evidence:** Activity logs show deletion operation
- **Prevention:** Implement Azure Policy to prevent deletion, enable resource locks

#### Category 2: Configuration Drift
- **Cause:** Deployment script error or manual configuration change
- **Evidence:** Configuration state doesn't match expected baseline
- **Prevention:** Implement Infrastructure as Code (IaC) validation, configuration drift detection

#### Category 3: Permission/Identity Issues
- **Cause:** Managed identity permissions revoked or SQL user deleted
- **Evidence:** Authentication errors in logs
- **Prevention:** Automated permission validation, least privilege reviews

#### Category 4: Network Connectivity
- **Cause:** VNet link deletion, NSG rule change, private endpoint misconfiguration
- **Evidence:** DNS resolution failures, connection timeouts
- **Prevention:** Network configuration monitoring, automated remediation

### 3.4 RCA Document Template

```markdown
# Root Cause Analysis: [Incident Title]

## Executive Summary
- **Incident Date:** [DATE]
- **Duration:** [X minutes]
- **Severity:** Sev1 (Critical)
- **Impact:** [Description of user impact]
- **Root Cause:** [One-line summary]
- **Resolution:** [One-line summary]

## Incident Details

### Alert Information
- **Alert Name:** SQL-Health-Endpoint-Unavailable-MultiRegion-y7njcffivri2q
- **Trigger Time:** [TIME]
- **Resolved Time:** [TIME]
- **Alert Condition:** Health endpoint failing in multiple regions

### Impact Assessment
- **Users Affected:** [Number/Percentage]
- **Services Impacted:** Web application, SQL database access
- **Failed Requests:** [Number from Application Insights]
- **Success Rate During Incident:** [Percentage]

### Timeline
[Use timeline from section 3.2]

## Root Cause

### Technical Root Cause
[Detailed explanation of what failed]

**Root Cause #1: Private DNS Zone VNet Link Missing**
- VNet link was [deleted/not created] for privatelink.database.windows.net
- App Service could not resolve SQL Server private endpoint
- Connection attempts routed to public endpoint (blocked by firewall)
- Error 47073: Deny Public Network Access

**Root Cause #2: Managed Identity SQL User Missing**
- SQL database user for managed identity was [deleted/not created]
- Authentication failed despite valid managed identity token
- Error: Login failed for user "."

### Contributing Factors
- [List any factors that contributed to the issue]
- [E.g., Lack of automated validation, manual changes, etc.]

## Resolution

### Immediate Actions Taken
1. Diagnostic script executed to identify root cause
2. [VNet link recreated / SQL user recreated]
3. App Service restarted to clear connection pool
4. Health endpoints verified
5. Application Insights confirmed service restoration

### Verification Steps
- Health endpoint returned "healthy" status
- Application Insights success rate: 100%
- No errors in last 15 minutes
- Availability tests passing from all regions

## Prevention & Action Items

### Immediate (Within 24 hours)
- [ ] Document incident in Azure DevOps
- [ ] Update runbook with lessons learned
- [ ] Verify backup restoration procedures

### Short-term (Within 1 week)
- [ ] Implement Azure Policy to prevent VNet link deletion
- [ ] Enable resource locks on critical networking resources
- [ ] Add automated validation of SQL user permissions
- [ ] Enhance monitoring alerts for configuration drift

### Long-term (Within 1 month)
- [ ] Implement automated remediation for common failures
- [ ] Create chaos engineering tests to validate resilience
- [ ] Enhance Infrastructure as Code validation
- [ ] Add pre-deployment validation gates

### Monitoring Enhancements
- [ ] Add alert for VNet link deletion (Activity Log alert)
- [ ] Add alert for SQL user permission changes
- [ ] Implement configuration drift detection
- [ ] Add synthetic transaction monitoring

## Lessons Learned

### What Went Well
- Alert detected issue within [X] minutes
- Diagnostic script quickly identified root cause
- Automated fix script restored service rapidly
- Communication was timely and accurate

### What Could Be Improved
- [Areas for improvement]
- [Process gaps identified]
- [Tool limitations discovered]

## Appendix

### Evidence
- Application Insights Query Results: [Link/Attachment]
- Azure Activity Logs: [Link/Attachment]
- Health Endpoint Responses: [Screenshots]
- Alert Notification: [Screenshot]

### Related Documentation
- DEPLOYMENT-SUMMARY.md
- BREAKFIX-GUIDE.md
- VALIDATION-GUIDE.md
- Architecture Diagrams
```

---

## PART 4: REFERENCE COMMANDS

### Quick Diagnostic Commands

```powershell
# Check App Service status
az webapp show `
  --name app-y7njcffivri2q `
  --resource-group sre-demo2-rg `
  --query "{Name:name, State:state, AvailabilityState:availabilityState}" `
  -o table

# Test health endpoints
Invoke-RestMethod -Uri "https://app-y7njcffivri2q.azurewebsites.net/health"
Invoke-RestMethod -Uri "https://app-y7njcffivri2q.azurewebsites.net/health/sql"

# Check VNet link status
az network private-dns link vnet list `
  --resource-group sre-demo2-rg `
  --zone-name privatelink.database.windows.net `
  --query "[].{Name:name, State:provisioningState}" `
  -o table

# Check managed identity
az webapp identity show `
  --name app-y7njcffivri2q `
  --resource-group sre-demo2-rg `
  --query "{PrincipalId:principalId, Type:type}" `
  -o table

# Check private endpoint
az network private-endpoint list `
  --resource-group sre-demo2-rg `
  --query "[?contains(name, 'sql')].{Name:name, State:provisioningState, PrivateIP:customDnsConfigs[0].ipAddresses[0]}" `
  -o table

# View recent alerts
az monitor metrics alert list `
  --resource-group sre-demo2-rg `
  --query "[].{Name:name, Enabled:enabled, Severity:severity, LastModified:lastUpdatedTime}" `
  -o table
```

### Quick Fix Commands

```powershell
# Recreate VNet link (if missing)
$vnetId = az network vnet show `
  --resource-group sre-demo2-rg `
  --name vnet-y7njcffivri2q `
  --query "id" -o tsv

az network private-dns link vnet create `
  --resource-group sre-demo2-rg `
  --zone-name privatelink.database.windows.net `
  --name vnet-y7njcffivri2q-link `
  --virtual-network $vnetId `
  --registration-enabled false

# Restart App Service
az webapp restart --name app-y7njcffivri2q --resource-group sre-demo2-rg

# View App Service logs
az webapp log tail --name app-y7njcffivri2q --resource-group sre-demo2-rg
```

### Application Insights Queries

```powershell
# Check recent request success rate
az monitor app-insights query `
  --app appi-y7njcffivri2q `
  --resource-group sre-demo2-rg `
  --analytics-query "requests | where timestamp > ago(10m) | summarize SuccessRate=countif(success==true)*100.0/count(), TotalRequests=count()"

# View recent exceptions
az monitor app-insights query `
  --app appi-y7njcffivri2q `
  --resource-group sre-demo2-rg `
  --analytics-query "exceptions | where timestamp > ago(10m) | project timestamp, type, outerMessage | take 10"

# Check SQL dependency failures
az monitor app-insights query `
  --app appi-y7njcffivri2q `
  --resource-group sre-demo2-rg `
  --analytics-query "dependencies | where timestamp > ago(10m) | where type == 'SQL' | where success == false | project timestamp, target, data, resultCode"

# Live tail app logs (streaming)
az webapp log tail --name app-y7njcffivri2q --resource-group sre-demo2-rg

# Check alert firing status
az monitor metrics alert list `
  --resource-group sre-demo2-rg `
  --query "[?contains(name, 'SQL')].{Name:name, Enabled:enabled, Severity:severity}" `
  -o table
```

### Azure Activity Log Queries

```powershell
# Check recent resource changes
az monitor activity-log list `
  --resource-group sre-demo2-rg `
  --start-time (Get-Date).AddHours(-2).ToString('yyyy-MM-ddTHH:mm:ssZ') `
  --query "[?contains(resourceId, 'privatelink') || contains(resourceId, 'sql-y7njcffivri2q')].{Time:eventTimestamp, Operation:operationName.value, Status:status.value, Caller:caller}" `
  -o table

# Check deployment history
az webapp deployment list `
  --name app-y7njcffivri2q `
  --resource-group sre-demo2-rg `
  --query "[].{Time:received_time, Status:status, Deployer:deployer}" `
  -o table
```

---

## ESCALATION PATH

### Level 1: On-Call Engineer
- **Action:** Follow this runbook
- **Expected Resolution Time:** 5-15 minutes
- **Escalate if:** Cannot resolve within 15 minutes or root cause is unclear

### Level 2: Senior SRE / Infrastructure Team
- **Contact:** [Team DL / Slack Channel: #sre-team]
- **Escalate if:** Root cause is outside runbook scope, multiple resources affected, or Azure platform issue suspected
- **Information to provide:** Alert name, start time, health endpoint responses, diagnostic output

### Level 3: Azure Support
- **Contact:** Open Azure Support ticket (Severity A - Critical)
- **Portal:** https://portal.azure.com/#blade/Microsoft_Azure_Support/HelpAndSupportBlade
- **Escalate if:** Azure platform outage, resource provisioning failures, or Microsoft service degradation
- **Information needed:** 
  - Subscription ID: 463a82d4-1896-4332-aeeb-618ee5a5aa93
  - Resource Group: sre-demo2-rg
  - Affected Resources: app-y7njcffivri2q, sql-y7njcffivri2q
  - Incident timestamps and error messages
  - Application Insights correlation IDs

---

## CONTACT INFORMATION

**Team:** SRE Team  
**On-Call Rotation:** [Link to PagerDuty/Opsgenie]  
**Slack Channel:** #sre-alerts  
**Email DL:** sre-team@company.com  
**Wiki:** [Link to internal wiki]  
**Azure Portal Resource Group:** https://portal.azure.com/#resource/subscriptions/463a82d4-1896-4332-aeeb-618ee5a5aa93/resourceGroups/sre-demo2-rg

---

## REVISION HISTORY

| Date | Version | Author | Changes |
|------|---------|--------|---------|
| 2026-01-12 | 2.0 | SRE Team | Refactored to use Az CLI instead of breakfix.ps1 script |
| 2026-01-11 | 1.0 | SRE Team | Initial runbook creation |

---

**END OF RUNBOOK**
