using './main.bicep'

param environmentName = readEnvironmentVariable('AZURE_ENV_NAME', 'dev')
param location = readEnvironmentVariable('AZURE_LOCATION', 'eastus')
param resourceGroupName = readEnvironmentVariable('AZURE_RESOURCE_GROUP', '')

// SQL Server Entra ID Admin Configuration
// These should be set before deployment
param sqlAdminObjectId = readEnvironmentVariable('AZURE_SQL_ADMIN_OBJECT_ID', '')
param sqlAdminPrincipalName = readEnvironmentVariable('AZURE_SQL_ADMIN_PRINCIPAL_NAME', '')
param sqlAdminLogin = 'sqladmin'

param sqlDatabaseName = 'FaultyWebAppDb'
param appServicePlanSku = 'P1v3'

param tags = {
  'azd-env-name': environmentName
  environment: environmentName
  application: 'FaultyWebApp'
}
