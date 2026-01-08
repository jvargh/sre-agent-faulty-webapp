@description('Location for all resources')
param location string

@description('Unique token for resource naming')
param resourceToken string

@description('Tags to apply to resources')
param tags object = {}

var vnetName = 'vnet-${resourceToken}'
var appServiceSubnetName = 'snet-appservice'
var sqlPrivateEndpointSubnetName = 'snet-sql-pe'

// Virtual Network
resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: appServiceSubnetName
        properties: {
          addressPrefix: '10.0.0.0/24'
          delegations: [
            {
              name: 'delegation'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        name: sqlPrivateEndpointSubnetName
        properties: {
          addressPrefix: '10.0.1.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
    ]
  }
}

// Private DNS Zone for SQL Server
resource sqlPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink${environment().suffixes.sqlServerHostname}'
  location: 'global'
  tags: tags
}

// Link Private DNS Zone to VNet
resource sqlPrivateDnsZoneVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: sqlPrivateDnsZone
  name: '${vnetName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

output vnetId string = vnet.id
output vnetName string = vnet.name
output appServiceIntegrationSubnetId string = vnet.properties.subnets[0].id
output sqlPrivateEndpointSubnetId string = vnet.properties.subnets[1].id
output sqlPrivateDnsZoneId string = sqlPrivateDnsZone.id
