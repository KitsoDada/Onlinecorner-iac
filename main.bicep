@description('Location for all resources.')
param location string = resourceGroup().location

@description('SQL Admin Username')
param sqlAdmin string

@secure()
@description('SQL Admin Password')
param sqlPassword string

@description('Resource prefix')
param prefix string = 'eshop'

@description('Environment tag')
param environment string = 'dev'

// Networking
resource vnet 'Microsoft.Network/virtualNetworks@2023-04-01' = {
  name: '${prefix}-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'default'
        properties: {
          addressPrefix: '10.0.1.0/24'
        }
      }
      {
        name: 'private-endpoints'
        properties: {
          addressPrefix: '10.0.2.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

// Module: SQL
module sqlModule 'sql.bicep' = {
  name: 'sqlDeployment'
  params: {
    sqlServerName: '${prefix}-sql-${uniqueString(resourceGroup().id)}'
    sqlDatabaseName: '${prefix}-db'
    sqlAdminUsername: sqlAdmin
    sqlAdminPassword: sqlPassword
    location: location
    environment: environment
  }
}

// Private DNS zone
resource sqlPrivateDnsZone 'Microsoft.Network/privateDnsZones@2023-05-01' = {
  name: 'privatelink.database.windows.net'
  location: 'global'
}

// VNet Link to DNS Zone
resource vnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2023-05-01' = {
  name: '${sqlPrivateDnsZone.name}-link'
  parent: sqlPrivateDnsZone
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
}

// Private Endpoint for SQL Server
resource sqlPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-05-01' = {
  name: '${prefix}-sql-pe'
  location: location
  properties: {
    subnet: {
      id: vnet.properties.subnets[1].id
    }
    privateLinkServiceConnections: [
      {
        name: 'sqlConnection'
        properties: {
          privateLinkServiceId: sqlModule.outputs.sqlServerResourceId
          groupIds: [ 'sqlServer' ]
        }
      }
    ]
  }
}

// Private DNS Zone Group
resource sqlPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-05-01' = {
  name: 'default'
  parent: sqlPrivateEndpoint
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'sqlDns'
        properties: {
          privateDnsZoneId: sqlPrivateDnsZone.id
        }
      }
    ]
  }
}

// App Service Plan
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: '${prefix}-asp'
  location: location
  sku: {
    name: 'P1v2'
    tier: 'PremiumV2'
    capacity: 1
  }
  properties: {
    reserved: false
  }
}

// Web App
resource webApp 'Microsoft.Web/sites@2023-01-01' = {
  name: '${prefix}-frontend'
  location: location
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      appSettings: [
        {
          name: 'SQL_CONNECTION_STRING'
          value: sqlModule.outputs.sqlConnectionString
        }
        {
          name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE'
          value: 'false'
        }
      ]
    }
  }
}

// AKS cluster (simplified)
resource aks 'Microsoft.ContainerService/managedClusters@2023-01-02-preview' = {
  name: '${prefix}-aks'
  location: location
  properties: {
    dnsPrefix: '${prefix}aksdns'
    agentPoolProfiles: [
      {
        name: 'nodepool1'
        count: 1
        vmSize: 'Standard_DS2_v2'
        osType: 'Linux'
        mode: 'System'
      }
    ]
    networkProfile: {
      networkPlugin: 'azure'
      dnsServiceIp: '10.2.0.10'
      serviceCidr: '10.2.0.0/24'
      dockerBridgeCidr: '172.17.0.1/16'
    }
  }
}
