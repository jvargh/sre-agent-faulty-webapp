@description('Location for all resources')
param location string

@description('Unique token for resource naming')
param resourceToken string

@description('SQL Server administrator login name')
param sqlAdminLogin string

@description('SQL Server administrator object ID from Entra ID')
param sqlAdminObjectId string

@description('SQL Server administrator principal name')
param sqlAdminPrincipalName string

@description('SQL Database name')
param databaseName string

@description('Subnet ID for private endpoint')
param subnetId string

@description('VNet ID for private endpoint')
param vnetId string

@description('Private DNS Zone ID for SQL')
param privateDnsZoneId string

@description('Tags to apply to resources')
param tags object = {}

var sqlServerName = 'sql-${resourceToken}'
var privateEndpointName = 'pe-${sqlServerName}'

// SQL Server with Entra ID authentication only
resource sqlServer 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: sqlServerName
  location: location
  tags: tags
  properties: {
    administratorLogin: sqlAdminLogin
    administratorLoginPassword: guid(subscription().id, resourceGroup().id, sqlServerName) // Placeholder - not used with Entra auth
    version: '12.0'
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Disabled' // Private endpoint only
    restrictOutboundNetworkAccess: 'Disabled'
    administrators: {
      administratorType: 'ActiveDirectory'
      principalType: 'User'
      login: sqlAdminPrincipalName
      sid: sqlAdminObjectId
      tenantId: subscription().tenantId
      azureADOnlyAuthentication: true // Entra ID only authentication
    }
  }
}

// SQL Database
resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-08-01-preview' = {
  parent: sqlServer
  name: databaseName
  location: location
  tags: tags
  sku: {
    name: 'Basic'
    tier: 'Basic'
    capacity: 5
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 2147483648 // 2GB
    catalogCollation: 'SQL_Latin1_General_CP1_CI_AS'
    zoneRedundant: false
    readScale: 'Disabled'
    requestedBackupStorageRedundancy: 'Local'
  }
}

// Private Endpoint for SQL Server
resource sqlPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: privateEndpointName
  location: location
  tags: tags
  properties: {
    subnet: {
      id: subnetId
    }
    privateLinkServiceConnections: [
      {
        name: privateEndpointName
        properties: {
          privateLinkServiceId: sqlServer.id
          groupIds: [
            'sqlServer'
          ]
        }
      }
    ]
  }
}

// Private DNS Zone Group
resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: sqlPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-database-windows-net'
        properties: {
          privateDnsZoneId: privateDnsZoneId
        }
      }
    ]
  }
}

output sqlServerName string = sqlServer.name
output sqlServerId string = sqlServer.id
output sqlServerFqdn string = sqlServer.properties.fullyQualifiedDomainName
output sqlDatabaseName string = sqlDatabase.name
