@description('The name of the Managed Cluster resource.')
param clusterName string = 'aksOnline-cornerCluster'

@description('The location of the Managed Cluster resource.')
param location string = resourceGroup().location

@description('Optional DNS prefix to use with hosted Kubernetes API server FQDN.')
param dnsPrefix string

@description('Disk size (in GB) to provision for each of the agent pool nodes. This value ranges from 0 to 1023. Specifying 0 will apply the default disk size for that agentVMSize.')
@minValue(0)
@maxValue(1023)
param osDiskSizeGB int = 0

@description('The number of nodes for the cluster.')
@minValue(1)
@maxValue(50)
param agentCount int = 3

@description('The size of the Virtual Machine.')
param agentVMSize string = 'standard_d2s_v3'

@description('User name for the Linux Virtual Machines.')
param linuxAdminUsername string

@description('Configure all linux machines with the SSH RSA public key string. Your key should include three parts, for example \'ssh-rsa AAAAB...snip...UcyupgH azureuser@linuxvm\'')
param sshRSAPublicKey string

@description('The name of virtual network.')
param vnetName string = 'Online-corner-vnet'

@description('The name of the public subnet.')
param publicSubnetName string = 'Online-corner-public-subnet'

@description('The name of the private subnet.')
param privateSubnetName string = 'Online-corner-private-subnet'

@description('The name of the Azure Container Registry.')
param acrName string = 'Online-corneracr${uniqueString(resourceGroup().id)}' // Globally unique name

@description('The name of the Application Gateway.')
param appGatewayName string = 'Online-corner-app-gateway'

@description('The name of the App Service Plan.')
param appServicePlanName string = 'Online-corner-app-service-plan'

@description('The name of the Web App.')
param webAppName string = 'Online-corner-webapp${uniqueString(resourceGroup().id)}' // Globally unique name

// @description('Webhook Name.')
// param webhookName string = 'Online-corner-webhook'

@description('The name of the container image.')
param containerImage string = 'Online-corner-product-service:latest' // Change to your container image name

@description('Client ID of the Service Principal used for AKS.')
@secure()
param aksServicePrincipalClientId string 

@description('DB connection string.')
param dbConnection string

@description('DB Host.')
param dbHost string

@description('DB Port.')
param dbPort string ='3306'

@description('DB Name.')
param dbName string = 'Online-corner'

@description('DB User.')
param dbUser string

@description('DB Password.')
@secure()
param dbPassword string

// Virtual Network
resource vnet 'Microsoft.Network/virtualNetworks@2021-05-01' = {
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

// Azure Container Registry
resource acr 'Microsoft.ContainerRegistry/registries@2021-06-01-preview' = {
  name: acrName
  location: location
  sku: {
    name: 'Premium' // Premium needed for private link/vnet integration
  }
  properties: {
    adminUserEnabled: true
    networkRuleSet: {
      defaultAction: 'Allow'
    }
  }
}

// Private Endpoint for ACR
resource acrPrivateEndpoint 'Microsoft.Network/privateEndpoints@2021-05-01' = {
  name: '${acrName}-pe'
  location: location
  properties: {
    subnet: {
      id: '${vnet.id}/subnets/${privateSubnetName}'
    }
    privateLinkServiceConnections: [
      {
        name: '${acrName}-connection'
        properties: {
          privateLinkServiceId: acr.id
          groupIds: [
            'registry'
          ]
        }
      }
    ]
  }
}

resource appGatewayPublicIp 'Microsoft.Network/publicIPAddresses@2021-05-01' = {
  name: '${appGatewayName}-ip'
  location: location
  sku: {
      name: 'Standard'
  }
  dependsOn: [
    vnet
  ]
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// Application Gateway
resource appGateway 'Microsoft.Network/applicationGateways@2021-05-01' = {
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
        name: 'appGatewayFrontendIp'
        properties: {
          publicIPAddress: {
            id: appGatewayPublicIp.id
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'httpPort'
        properties: {
          port: 80
        }
      }
      {
        name: 'httpsPort'
        properties: {
          port: 443
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'aksBackendPool'
        properties: {} // Will be populated after AKS is created
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'aksHttpSettings'
        properties: {
          port: 80
          protocol: 'Http'
          cookieBasedAffinity: 'Disabled'
          requestTimeout: 20
        }
      }
    ]
    httpListeners: [
      {
        name: 'aksHttpListener'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', appGatewayName, 'appGatewayFrontendIp')
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', appGatewayName, 'httpPort')
          }
          protocol: 'Http'
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'aksRoutingRule'
        properties: {
          ruleType: 'Basic'
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', appGatewayName, 'aksHttpListener')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', appGatewayName, 'aksBackendPool')
          }
          backendHttpSettings: {
            id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', appGatewayName, 'aksHttpSettings')
          }
        }
      }
    ]
  }
}

resource aks 'Microsoft.ContainerService/managedClusters@2024-02-01' = {
  name: clusterName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: dnsPrefix
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
        osDiskSizeGB: osDiskSizeGB
        count: agentCount
        vmSize: agentVMSize
        osType: 'Linux'
        mode: 'System'
        type: 'VirtualMachineScaleSets'
        vnetSubnetID: '${vnet.id}/subnets/${privateSubnetName}'
        enableNodePublicIP: false
        maxPods: 30
      }
    ]
    servicePrincipalProfile: {
      clientId: aksServicePrincipalClientId
    }
    linuxProfile: {
      adminUsername: linuxAdminUsername
      ssh: {
        publicKeys: [
          {
            keyData: sshRSAPublicKey
          }
        ]
      }
    }
    networkProfile: {
      networkPlugin: 'azure'
      serviceCidr: '10.2.0.0/16'
      dnsServiceIP: '10.2.0.10'
      loadBalancerSku: 'standard'
    }
  }
}

// App Service 
resource appServicePlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: appServicePlanName
  location: location
  sku: {
    name: 'P1v2' // Change if needed
    tier: 'PremiumV2'
  }
  kind: 'linux'
  properties: {
    reserved: true
  }
}

resource webApp 'Microsoft.Web/sites@2022-09-01' = {
  name: webAppName
  location: location
  kind: 'app,linux,container'
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      linuxFxVersion: 'DOCKER|${acr.properties.loginServer}/${containerImage}'
      appSettings: [
        {
          name: 'DOCKER_REGISTRY_SERVER_URL'
          value: 'https://${acr.properties.loginServer}/Online-corner-product-service'
        }
        {
          name: 'DOCKER_REGISTRY_SERVER_USERNAME'
          value: acr.properties.adminUserEnabled ? acr.properties.loginServer : ''
        }
        {
          name: 'DOCKER_REGISTRY_SERVER_PASSWORD'
          value: acr.properties.adminUserEnabled ? listCredentials(acr.id, '2023-07-01').passwords[0].value : ''
        }
        {
          name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE'
          value: 'false'
        }
        {
          name: 'DOCKER_ENABLE_CI'
          value: 'true' // Enables Continuous Deployment
        }
        {
          name: 'DB_CONNECTION'
          value: dbConnection
        }
        {
          name: 'DB_HOST'
          value: dbHost
        }
        {
          name: 'DB_PORT'
          value: dbPort
        }
        {
          name: 'DB_NAME'
          value: dbName
        }
        {
          name: 'DB_USER'
          value: dbUser
        }
        {
          name: 'DB_PASSWORD'
          value: dbPassword
        }
      ]
    }
  }
}

output controlPlaneFQDN string = aks.properties.fqdn
output aksClusterName string = aks.name
output acrName string = acr.name
output acrLoginServer string = acr.properties.loginServer
output appGatewayPublicIp string = appGatewayPublicIp.properties.ipAddress
output webAppUrl string = 'https://${webApp.properties.defaultHostName}'
