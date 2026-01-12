@description('Location for all resources')
param location string

@description('Resource token for unique naming')
param resourceToken string

@description('Web app name to monitor')
param webAppName string

@description('Web app URL to monitor')
param webAppUrl string

@description('Tags to apply to resources')
param tags object = {}

// Application Insights with Log Analytics
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: 'log-${resourceToken}'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: 1
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-${resourceToken}'
  location: location
  kind: 'web'
  tags: tags
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
    RetentionInDays: 30
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Availability Test for /health/sql endpoint
resource healthAvailabilityTest 'Microsoft.Insights/webtests@2022-06-15' = {
  name: 'webtest-health-sql-${resourceToken}'
  location: location
  tags: union(tags, {
    'hidden-link:${appInsights.id}': 'Resource'
  })
  kind: 'standard'
  properties: {
    Name: 'SQL Health Endpoint Test'
    Description: 'Monitors /health/sql endpoint for unhealthy status'
    Enabled: true
    Frequency: 300 // 5 minutes
    Timeout: 30
    Kind: 'standard'
    RetryEnabled: true
    Locations: [
      {
        Id: 'us-va-ash-azr' // East US
      }
      {
        Id: 'us-il-ch1-azr' // Central US
      }
      {
        Id: 'us-ca-sjc-azr' // West US
      }
    ]
    Request: {
      RequestUrl: '${webAppUrl}/health/sql'
      HttpVerb: 'GET'
      ParseDependentRequests: false
    }
    ValidationRules: {
      ExpectedHttpStatusCode: 200
      SSLCheck: true
      SSLCertRemainingLifetimeCheck: 7
      ContentValidation: {
        ContentMatch: '"status":"healthy"'
        IgnoreCase: true
        PassIfTextFound: true
      }
    }
    SyntheticMonitorId: 'webtest-health-sql-${resourceToken}'
  }
}

// Action Group for alerts
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'ag-health-${resourceToken}'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'HealthAlert'
    enabled: true
    emailReceivers: []
    smsReceivers: []
    webhookReceivers: []
    azureAppPushReceivers: []
    itsmReceivers: []
    automationRunbookReceivers: []
    voiceReceivers: []
    logicAppReceivers: []
    azureFunctionReceivers: []
    armRoleReceivers: [
      {
        name: 'Monitoring Contributor'
        roleId: '749f88d5-cbae-40b8-bcfc-e573ddc772fa' // Monitoring Contributor role
        useCommonAlertSchema: true
      }
    ]
  }
}

// Metric Alert Rule for Availability Test Failures
resource availabilityAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'SQL-Health-Endpoint-Unavailable-MultiRegion-${resourceToken}'
  location: 'global'
  tags: tags
  properties: {
    description: 'Critical: SQL health endpoint is failing availability checks from multiple Azure regions'
    severity: 1 // Critical
    enabled: true
    scopes: [
      appInsights.id
      healthAvailabilityTest.id
    ]
    evaluationFrequency: 'PT1M' // Every 1 minute
    windowSize: 'PT5M' // Over 5 minutes
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.WebtestLocationAvailabilityCriteria'
      webTestId: healthAvailabilityTest.id
      componentId: appInsights.id
      failedLocationCount: 2 // Alert if 2 or more locations fail
    }
    autoMitigate: true
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

// Scheduled Query Alert for Unhealthy Status Detection
resource unhealthyStatusAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'SQL-Database-Connection-Unhealthy-${resourceToken}'
  location: location
  tags: tags
  properties: {
    displayName: 'SQL Database Connection Unhealthy'
    description: 'Critical: Application cannot connect to SQL database - check private endpoint, DNS, and managed identity'
    severity: 1 // Critical
    enabled: true
    evaluationFrequency: 'PT5M' // Every 5 minutes
    windowSize: 'PT5M' // Over 5 minutes
    scopes: [
      appInsights.id
    ]
    criteria: {
      allOf: [
        {
          query: '''
availabilityResults
| where name == "SQL Health Endpoint Test"
| where success == false
| summarize FailureCount = count() by bin(timestamp, 5m)
| where FailureCount > 0
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: true
    actions: {
      actionGroups: [
        actionGroup.id
      ]
    }
  }
}

// App Service Metric Alert - High HTTP 5xx errors
resource http5xxAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'App-Service-HTTP-Server-Errors-Spike-${resourceToken}'
  location: 'global'
  tags: tags
  properties: {
    description: 'Warning: App Service experiencing high rate of HTTP 5xx server errors (>10 in 5 minutes)'
    severity: 2 // Warning
    enabled: true
    scopes: [
      resourceId('Microsoft.Web/sites', webAppName)
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'Http5xxErrors'
          metricName: 'Http5xx'
          metricNamespace: 'Microsoft.Web/sites'
          operator: 'GreaterThan'
          threshold: 10
          timeAggregation: 'Total'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    autoMitigate: true
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

// App Service Metric Alert - High Response Time
resource responseTimeAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'App-Service-Slow-Response-Time-${resourceToken}'
  location: 'global'
  tags: tags
  properties: {
    description: 'Info: App Service response time exceeds threshold (>5 seconds average) - check database performance'
    severity: 3 // Informational
    enabled: true
    scopes: [
      resourceId('Microsoft.Web/sites', webAppName)
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'ResponseTime'
          metricName: 'AverageResponseTime'
          metricNamespace: 'Microsoft.Web/sites'
          operator: 'GreaterThan'
          threshold: 5 // 5 seconds
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    autoMitigate: true
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

output appInsightsName string = appInsights.name
output appInsightsId string = appInsights.id
output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey
output appInsightsConnectionString string = appInsights.properties.ConnectionString
output logAnalyticsWorkspaceId string = logAnalytics.id
output actionGroupId string = actionGroup.id
output healthAvailabilityTestId string = healthAvailabilityTest.id
