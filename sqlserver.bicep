@description('The name of the SQL Server.')
param sqlServerName string

@secure()
@description('The administrator username for the SQL Server.')
param adminUsername string

@secure()
@description('The administrator password for the SQL Server.')
param adminPassword string

@description('The location where the SQL Server will be deployed.')
param location string = resourceGroup().location

resource sqlServer 'Microsoft.Sql/servers@2022-05-01-preview' = {
  name: sqlServerName
  location: location
  properties: {
    administratorLogin: adminUsername
    administratorLoginPassword: adminPassword
  }
}

output sqlServerName string = sqlServer.name
output sqlServerFQDN string = sqlServer.properties.fullyQualifiedDomainName
