@description('Name of the shop Container App')
param appName string = 'gelatai-shops'

@description('Azure region of the existing Container Apps environment')
param location string = resourceGroup().location

@description('Full ACR image reference')
param containerImage string

@description('Writable Fabric SQL database server discovered from the Fabric API')
param sqlServer string

@description('Physical Fabric SQL database name discovered from the Fabric API')
param sqlDatabase string

@description('Existing Container Apps environment name')
param environmentName string = 'gelatai-factory-env'

@description('Existing Azure Container Registry name')
param acrName string = 'gelataiacr'

@description('Existing user-assigned identity used for ACR image pulls')
param acrPullIdentityName string = 'gelatai-factory-acr-identity'

resource environment 'Microsoft.App/managedEnvironments@2024-03-01' existing = {
  name: environmentName
}

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: acrName
}

resource acrPullIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: acrPullIdentityName
}

resource shopApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: appName
  location: location
  identity: {
    type: 'SystemAssigned, UserAssigned'
    userAssignedIdentities: {
      '${acrPullIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: environment.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 8080
        transport: 'http'
        allowInsecure: false
      }
      registries: [
        {
          server: registry.properties.loginServer
          identity: acrPullIdentity.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'apishop'
          image: containerImage
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            {
              name: 'Sales__Destination'
              value: 'Sql'
            }
            {
              name: 'Sql__Server'
              value: sqlServer
            }
            {
              name: 'Sql__Database'
              value: sqlDatabase
            }
            {
              name: 'Sql__Authentication'
              value: 'ManagedIdentity'
            }
          ]
          probes: [
            {
              type: 'Startup'
              httpGet: {
                path: '/health'
                port: 8080
              }
              initialDelaySeconds: 1
              periodSeconds: 5
              failureThreshold: 30
            }
            {
              type: 'Liveness'
              httpGet: {
                path: '/health'
                port: 8080
              }
              initialDelaySeconds: 10
              periodSeconds: 30
              failureThreshold: 3
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/health'
                port: 8080
              }
              initialDelaySeconds: 5
              periodSeconds: 10
              failureThreshold: 3
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
    }
  }
}

output appName string = shopApp.name
output appUrl string = 'https://${shopApp.properties.configuration.ingress.fqdn}'
