@description('Name of the SQL Server.')
param sqlServerName string = 'eshop-sql-${uniqueString(resourceGroup().id)}'

@description('Name of the SQL Database.')
param sqlDatabaseName string = 'eshop-db'

@description('Administrator username for SQL Server.')
param sqlAdminUsername string = 'eshopadmin'

@secure()
@description('Administrator password for SQL Server.')
param sqlAdminPassword string

@description('Location for SQL resources (e.g., southafricanorth).')
param location string = 'southafricanorth'

@description('Environment tag (e.g., dev, prod).')
param environment string = 'dev'

// SQL Server
resource sqlServer 'Microsoft.Sql/servers@2022-05-01-preview' = {
  name: sqlServerName
  location: location
  tags: {
    environment: environment
    application: 'ecommerce'
  }
  properties: {
    administratorLogin: sqlAdminUsername
    administratorLoginPassword: sqlAdminPassword
    version: '12.0'
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    restrictOutboundNetworkAccess: 'Disabled'
  }
}

// SQL Database
resource sqlDatabase 'Microsoft.Sql/servers/databases@2022-05-01-preview' = {
  parent: sqlServer
  name: sqlDatabaseName
  location: location
  sku: {
    name: 'S0'
    tier: 'Standard'
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 268435456000
    zoneRedundant: false
    licenseType: 'LicenseIncluded'
  }
}

// Allow Azure services to access the SQL Server
resource firewallRule 'Microsoft.Sql/servers/firewallRules@2022-05-01-preview' = {
  parent: sqlServer
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}
