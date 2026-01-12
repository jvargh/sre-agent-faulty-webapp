@description('Location for all resources')
param location string

@description('Unique token for resource naming')
param resourceToken string

@description('App Service Plan SKU')
param appServicePlanSku string

@description('Subnet ID for VNet integration')
param vnetIntegrationSubnetId string

@description('SQL Server FQDN')
param sqlServerFqdn string

@description('SQL Database name')
param sqlDatabaseName string

@description('Application Insights connection string')
param appInsightsConnectionString string = ''

@description('Tags to apply to resources')
param tags object = {}

var appServicePlanName = 'plan-${resourceToken}'
var webAppName = 'app-${resourceToken}'

// App Service Plan
resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: appServicePlanName
  location: location
  tags: tags
  sku: {
    name: appServicePlanSku
  }
  kind: 'linux'
  properties: {
    reserved: true
  }
}

// Web App with VNet Integration
resource webApp 'Microsoft.Web/sites@2023-12-01' = {
  name: webAppName
  location: location
  tags: union(tags, {
    'azd-service-name': 'web'
  })
  kind: 'app,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    virtualNetworkSubnetId: vnetIntegrationSubnetId
    vnetRouteAllEnabled: true
    vnetContentShareEnabled: false
    vnetImagePullEnabled: false
    siteConfig: {
      linuxFxVersion: 'DOTNETCORE|8.0'
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      http20Enabled: true
      alwaysOn: true
      vnetRouteAllEnabled: true
      publicNetworkAccess: 'Enabled' // App itself is public, but accesses SQL via private endpoint
      appSettings: [
        {
          name: 'ASPNETCORE_ENVIRONMENT'
          value: 'Production'
        }
        {
          name: 'WEBSITE_HTTPLOGGING_RETENTION_DAYS'
          value: '7'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsightsConnectionString
        }
        {
          name: 'ApplicationInsightsAgent_EXTENSION_VERSION'
          value: '~3'
        }
        {
          name: 'XDT_MicrosoftApplicationInsights_Mode'
          value: 'recommended'
        }
      ]
      connectionStrings: [
        {
          name: 'DefaultConnection'
          connectionString: 'Server=tcp:${sqlServerFqdn},1433;Initial Catalog=${sqlDatabaseName};Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'
          type: 'SQLAzure'
        }
      ]
    }
  }
}

// Web App Configuration - Additional settings
resource webAppConfig 'Microsoft.Web/sites/config@2023-12-01' = {
  parent: webApp
  name: 'web'
  properties: {
    numberOfWorkers: 1
    netFrameworkVersion: 'v8.0'
    requestTracingEnabled: false
    remoteDebuggingEnabled: false
    httpLoggingEnabled: true
    detailedErrorLoggingEnabled: true
    publishingUsername: '$${webAppName}'
    use32BitWorkerProcess: false
    healthCheckPath: '/health'
    managedPipelineMode: 'Integrated'
    virtualApplications: [
      {
        virtualPath: '/'
        physicalPath: 'site\\wwwroot'
        preloadEnabled: true
      }
    ]
    loadBalancing: 'LeastRequests'
    autoHealEnabled: false
    cors: {
      allowedOrigins: [
        'https://portal.azure.com'
      ]
    }
  }
}

output webAppName string = webApp.name
output webAppId string = webApp.id
output webAppUrl string = 'https://${webApp.properties.defaultHostName}'
output managedIdentityPrincipalId string = webApp.identity.principalId
output appServicePlanId string = appServicePlan.id
