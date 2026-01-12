targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the environment that can be used as part of naming resource convention')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string

@description('Name of the resource group')
param resourceGroupName string = ''

@description('SQL Server administrator login name')
param sqlAdminLogin string = 'sqladmin'

@description('SQL Server administrator object ID from Entra ID')
param sqlAdminObjectId string

@description('SQL Server administrator principal name')
param sqlAdminPrincipalName string

@description('SQL Database name')
param sqlDatabaseName string = 'FaultyWebAppDb'

@description('App Service Plan SKU')
param appServicePlanSku string = 'P1v3'

@description('Tags to apply to all resources')
param tags object = {}

// Generate unique names
var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))

// Resource group
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: !empty(resourceGroupName) ? resourceGroupName : '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: union(tags, {
    'azd-env-name': environmentName
  })
}

// Network infrastructure
module network './modules/network.bicep' = {
  scope: rg
  name: 'network-deployment'
  params: {
    location: location
    resourceToken: resourceToken
    tags: tags
  }
}

// SQL Server with private endpoint
module sql './modules/sql.bicep' = {
  scope: rg
  name: 'sql-deployment'
  params: {
    location: location
    resourceToken: resourceToken
    sqlAdminLogin: sqlAdminLogin
    sqlAdminObjectId: sqlAdminObjectId
    sqlAdminPrincipalName: sqlAdminPrincipalName
    databaseName: sqlDatabaseName
    subnetId: network.outputs.sqlPrivateEndpointSubnetId
    vnetId: network.outputs.vnetId
    privateDnsZoneId: network.outputs.sqlPrivateDnsZoneId
    tags: tags
  }
}

// App Service with VNet integration
module webapp './modules/webapp.bicep' = {
  scope: rg
  name: 'webapp-deployment'
  params: {
    location: location
    resourceToken: resourceToken
    appServicePlanSku: appServicePlanSku
    vnetIntegrationSubnetId: network.outputs.appServiceIntegrationSubnetId
    sqlServerFqdn: sql.outputs.sqlServerFqdn
    sqlDatabaseName: sqlDatabaseName
    appInsightsConnectionString: ''
    tags: tags
  }
}

// Monitoring and alerts
module monitoring './modules/monitoring.bicep' = {
  scope: rg
  name: 'monitoring-deployment'
  params: {
    location: location
    resourceToken: resourceToken
    webAppName: webapp.outputs.webAppName
    webAppUrl: webapp.outputs.webAppUrl
    tags: tags
  }
}

// Update webapp with Application Insights connection string
module webappConfig './modules/webapp-config.bicep' = {
  scope: rg
  name: 'webapp-config-deployment'
  params: {
    webAppName: webapp.outputs.webAppName
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
  }
}

// Outputs for azd
output AZURE_LOCATION string = location
output AZURE_RESOURCE_GROUP string = rg.name
output AZURE_SQL_SERVER_NAME string = sql.outputs.sqlServerName
output AZURE_SQL_DATABASE_NAME string = sqlDatabaseName
output AZURE_WEBAPP_NAME string = webapp.outputs.webAppName
output AZURE_WEBAPP_URL string = webapp.outputs.webAppUrl
output AZURE_WEBAPP_IDENTITY_PRINCIPAL_ID string = webapp.outputs.managedIdentityPrincipalId
output AZURE_APPINSIGHTS_NAME string = monitoring.outputs.appInsightsName
output AZURE_APPINSIGHTS_CONNECTION_STRING string = monitoring.outputs.appInsightsConnectionString
