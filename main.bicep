param location string = resourceGroup().location
param acrName string
param vnetName string = 'Online-corner-vnet1'
param publicSubnetName string = 'Online-corner-public-subnet'
param privateSubnetName string = 'Online-corner-private-subnet'
param aksName string = 'aksOnline-cornerCluster'
param dnsPrefix string = 'onlinecornerdns'
param agentCount int = 2
param agentVMSize string = 'Standard_DS2_v2'
param osDiskSizeGB int = 30
param appGatewayName string = 'online-corner-appgw'
param appServicePlanName string = 'online-corner-plan'
param webAppName string = 'online-corner-webapp'

@description('The name of the container image in ACR, e.g. "sample-nodejs"')
param imageName string = 'sample-nodejs'

@description('The tag of the container image, e.g. "latest" or "v1.0.0"')
param imageTag string = 'latest'

resource acr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' = {
  name: acrName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: true
  }
}

var acrLoginServer = reference(acr.id, '2023-01-01-preview').loginServer
var linuxFxVersion = 'DOCKER|${acrLoginServer}/${imageName}:${imageTag}'

resource vnet 'Microsoft.Network/virtualNetworks@2023-04-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: publicSubnetName
        properties: {
          addressPrefix: '10.0.1.0/24'
        }
      }
      {
        name: privateSubnetName
        properties: {
          addressPrefix: '10.0.2.0/24'
        }
      }
    ]
  }
}

resource publicIP 'Microsoft.Network/publicIPAddresses@2023-04-01' = {
  name: 'online-corner-appgw-pip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource appGateway 'Microsoft.Network/applicationGateways@2023-04-01' = {
  name: appGatewayName
  location: location
  properties: {
    sku: {
      name: 'Standard_v2'
      tier: 'Standard_v2'
      capacity: 2
    }
    gatewayIPConfigurations: [
      {
        name: 'appGatewayIpConfig'
        properties: {
          subnet: {
            id: '${vnet.id}/subnets/${publicSubnetName}'
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'appGatewayFrontendIP'
        properties: {
          publicIPAddress: {
            id: publicIP.id
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'appGatewayFrontendPort'
        properties: {
          port: 80
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'appGatewayBackendPool'
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'appGatewayBackendHttpSettings'
        properties: {
          port: 80
          protocol: 'Http'
          cookieBasedAffinity: 'Disabled'
        }
      }
    ]
    httpListeners: [
      {
        name: 'appGatewayHttpListener'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', appGatewayName, 'appGatewayFrontendIP')
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', appGatewayName, 'appGatewayFrontendPort')
          }
          protocol: 'Http'
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'rule1'
        properties: {
          ruleType: 'Basic'
          priority: 100
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', appGatewayName, 'appGatewayHttpListener')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', appGatewayName, 'appGatewayBackendPool')
          }
          backendHttpSettings: {
            id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', appGatewayName, 'appGatewayBackendHttpSettings')
          }
        }
      }
    ]
  }
}

resource aks 'Microsoft.ContainerService/managedClusters@2024-02-01' = {
  name: aksName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: dnsPrefix
    networkProfile: {
      networkPlugin: 'azure'
      serviceCidr: '10.100.0.0/16'
      dnsServiceIP: '10.100.0.10'
    }
    addonProfiles: {
      ingressApplicationGateway: {
        enabled: true
        config: {
          applicationGatewayId: appGateway.id
        }
      }
    }
    agentPoolProfiles: [
      {
        name: 'agentpool'
        count: agentCount
        vmSize: agentVMSize
        osType: 'Linux'
        mode: 'System'
        osDiskSizeGB: osDiskSizeGB
        type: 'VirtualMachineScaleSets'
        vnetSubnetID: '${vnet.id}/subnets/${privateSubnetName}'
        enableNodePublicIP: false
        maxPods: 30
      }
    ]
  }
}

resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: appServicePlanName
  location: location
  sku: {
    name: 'B1'
    tier: 'Basic'
    size: 'B1'
    capacity: 1
  }
  properties: {
    reserved: true
  }
}

resource webApp 'Microsoft.Web/sites@2023-01-01' = {
  name: webAppName
  location: location
  identity: {
    type: 'SystemAssigned'  // Enable managed identity
  }
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      linuxFxVersion: linuxFxVersion
    }
    httpsOnly: true
  }
  kind: 'app,linux,container'
}

// Assign AcrPull role to Web App's managed identity on the ACR
resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(webApp.id, 'acrpull-role')
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull Role ID
    principalId: webApp.identity.principalId
  }
  dependsOn: [
    webApp
    acr
  ]
}

//
// Outputs
//
output controlPlaneFQDN string = aks.properties.fqdn
output aksClusterName string = aks.name
output acrName string = acr.name
output appGatewayPublicIp string = publicIP.properties.ipAddress
output webAppUrl string = webApp.properties.defaultHostName
