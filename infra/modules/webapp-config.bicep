@description('Web app name')
param webAppName string

@description('Application Insights connection string')
param appInsightsConnectionString string

resource webApp 'Microsoft.Web/sites@2023-12-01' existing = {
  name: webAppName
}

resource webAppSettings 'Microsoft.Web/sites/config@2023-12-01' = {
  name: 'appsettings'
  parent: webApp
  properties: {
    APPLICATIONINSIGHTS_CONNECTION_STRING: appInsightsConnectionString
    ApplicationInsightsAgent_EXTENSION_VERSION: '~3'
    XDT_MicrosoftApplicationInsights_Mode: 'recommended'
  }
}
