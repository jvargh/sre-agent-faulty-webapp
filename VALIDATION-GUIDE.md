# Application Insights Validation Guide

This guide documents the steps to validate that Application Insights is properly configured and receiving telemetry from the web application.

## Prerequisites

- Azure CLI installed and authenticated
- Access to Azure Portal
- PowerShell terminal

## Validation Steps

### Step 1: Verify Application Insights Configuration

Check that the web app has Application Insights settings configured:

```powershell
az webapp config appsettings list `
  --name app-y7njcffivri2q `
  --resource-group sre-demo2-rg `
  --query "[?name=='APPLICATIONINSIGHTS_CONNECTION_STRING' || name=='ApplicationInsightsAgent_EXTENSION_VERSION' || name=='XDT_MicrosoftApplicationInsights_Mode'].{Name:name, Value:value}" `
  -o table
```

**Expected Output:**
- `APPLICATIONINSIGHTS_CONNECTION_STRING` - Should have InstrumentationKey
- `ApplicationInsightsAgent_EXTENSION_VERSION` - Should be `~3`
- `XDT_MicrosoftApplicationInsights_Mode` - Should be `recommended`

### Step 2: Generate Traffic to the Application

Make requests to the web application to generate telemetry:

```powershell
# Generate test traffic
Invoke-RestMethod -Uri "https://app-y7njcffivri2q.azurewebsites.net/" -Method GET | Out-Null
Invoke-RestMethod -Uri "https://app-y7njcffivri2q.azurewebsites.net/health" -Method GET | Out-Null
Invoke-RestMethod -Uri "https://app-y7njcffivri2q.azurewebsites.net/health/sql" -Method GET | Out-Null
```

Wait 30-60 seconds for telemetry to propagate to Application Insights.

### Step 3: Query Availability Test Results

Check if availability tests are running and collecting data:

```powershell
az monitor app-insights query `
  --app appi-y7njcffivri2q `
  --resource-group sre-demo2-rg `
  --analytics-query "availabilityResults | where timestamp > ago(10m) | project timestamp, name, success, duration, location | order by timestamp desc | take 5" `
  --output json
```

**What to Look For:**
- `name`: "SQL Health Endpoint Test"
- `success`: "1" (success) or "0" (failure)
- `duration`: Response time in milliseconds
- `location`: Test location (East US, North Central US, West US)

### Step 4: Query Web Application Requests

Check for request telemetry from the web application:

```powershell
az monitor app-insights query `
  --app appi-y7njcffivri2q `
  --resource-group sre-demo2-rg `
  --analytics-query "requests | where timestamp > ago(10m) | summarize Count=count() by name, resultCode | order by Count desc" `
  --output table
```

**Note:** Request telemetry may take 2-5 minutes to appear after initial Application Insights configuration.

### Step 5: View Live Metrics in Azure Portal

For real-time telemetry visualization:

1. Navigate to Azure Portal
2. Go to Resource Groups → `sre-demo2-rg` → `appi-y7njcffivri2q`
3. Click **Live Metrics** in the left menu
4. You should see:
   - Incoming request rate
   - Server response times
   - Dependency call rates
   - Server performance metrics

**Direct Link:**
```
https://portal.azure.com/#resource/subscriptions/463a82d4-1896-4332-aeeb-618ee5a5aa93/resourceGroups/sre-demo2-rg/providers/Microsoft.Insights/components/appi-y7njcffivri2q/livemetrics
```

## Expected Results

### ✅ Successful Validation

- **Configuration**: All three Application Insights settings present
- **Availability Tests**: Running every 5 minutes from multiple regions
- **Telemetry**: Data appearing in Application Insights queries
- **Live Metrics**: Real-time data visible in portal

### ❌ Troubleshooting

If telemetry is not appearing:

1. **Check Configuration**:
   ```powershell
   az webapp show --name app-y7njcffivri2q --resource-group sre-demo2-rg --query "identity"
   ```

2. **Restart Web App** (clears any cached configuration):
   ```powershell
   az webapp restart --name app-y7njcffivri2q --resource-group sre-demo2-rg
   ```

3. **Wait 5-10 Minutes**: Application Insights agent may need time to initialize after first configuration

4. **Check Application Insights Ingestion**:
   ```powershell
   az monitor app-insights component show `
     --app appi-y7njcffivri2q `
     --resource-group sre-demo2-rg `
     --query "{IngestionMode:properties.IngestionMode, ConnectionString:properties.ConnectionString}"
   ```

## Advanced Queries

### Query All Request Types
```kusto
requests 
| where timestamp > ago(1h)
| summarize Count=count(), AvgDuration=avg(duration) by name, resultCode
| order by Count desc
```

### Query SQL Dependencies
```kusto
dependencies
| where timestamp > ago(1h)
| where type == "SQL"
| project timestamp, name, target, duration, success, resultCode
| order by timestamp desc
| take 20
```

### Query Exceptions
```kusto
exceptions
| where timestamp > ago(1h)
| project timestamp, type, outerMessage, innermostMessage
| order by timestamp desc
| take 10
```

## Validation Checklist

- [ ] Application Insights connection string configured on web app
- [ ] Application Insights agent extension enabled (~3)
- [ ] Telemetry mode set to recommended
- [ ] Availability tests running from multiple regions
- [ ] Availability test results appearing in queries
- [ ] Web app generating traffic successfully
- [ ] Request telemetry appearing in Application Insights (may take 2-5 min)
- [ ] Live Metrics showing real-time data in portal
- [ ] Alerts configured and referencing Application Insights

## Summary

Application Insights provides:
- **Availability Monitoring**: Health endpoint checks from multiple regions every 5 minutes
- **Request Telemetry**: All HTTP requests, response codes, durations
- **Dependency Tracking**: SQL database calls, external API calls
- **Exception Tracking**: Errors and stack traces
- **Performance Metrics**: Server CPU, memory, response times
- **Alert Integration**: Powers all monitoring alerts for the application

Once validated, the monitoring infrastructure will automatically alert on:
- SQL health endpoint failures (Critical)
- SQL database connection issues (Critical)
- High HTTP 5xx errors (Warning)
- Slow response times (Informational)
