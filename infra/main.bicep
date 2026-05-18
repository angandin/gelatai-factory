@description('Base name for all resources')
param appName string = 'gelatai-factory'

@description('Azure region')
param location string = resourceGroup().location

@description('Container image (e.g. myacr.azurecr.io/apifactory:latest)')
param containerImage string

@description('Event Hub connection string (optional)')
@secure()
param eventHubConnectionString string = ''

@description('Event Hub name (optional)')
param eventHubName string = ''

// ============= Storage Account + File Share =============
var storageAccountName = replace('${take(appName, 16)}stor', '-', '')

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
  }
}

resource fileService 'Microsoft.Storage/storageAccounts/fileServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-05-01' = {
  parent: fileService
  name: 'appdata'
  properties: {
    shareQuota: 1
  }
}

// ============= Container App Environment =============
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${appName}-logs'
  location: location
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

resource containerEnv 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: '${appName}-env'
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
  }
}

// Mount the Azure Files share as a storage volume on the environment
resource envStorage 'Microsoft.App/managedEnvironments/storages@2024-03-01' = {
  parent: containerEnv
  name: 'appdata'
  properties: {
    azureFile: {
      accountName: storageAccount.name
      accountKey: storageAccount.listKeys().keys[0].value
      shareName: fileShare.name
      accessMode: 'ReadWrite'
    }
  }
}

// ============= Container App =============
resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: appName
  location: location
  dependsOn: [envStorage]
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: containerEnv.id
    configuration: {
      secrets: empty(eventHubConnectionString) ? [] : [
        {
          name: 'eventhub-conn'
          value: eventHubConnectionString
        }
      ]
      ingress: {
        external: true
        targetPort: 8080
        transport: 'http'
        allowInsecure: false
      }
    }
    template: {
      containers: [
        {
          name: 'apifactory'
          image: containerImage
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: concat(
            [
              { name: 'DATA_DIR', value: '/app/data' }
              { name: 'EventHub__Name', value: eventHubName }
            ],
            empty(eventHubConnectionString) ? [] : [
              { name: 'EventHub__ConnectionString', secretRef: 'eventhub-conn' }
            ]
          )
          volumeMounts: [
            {
              volumeName: 'appdata'
              mountPath: '/app/data'
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 3
      }
      volumes: [
        {
          name: 'appdata'
          storageType: 'AzureFile'
          storageName: envStorage.name
        }
      ]
    }
  }
}

output appUrl string = 'https://${containerApp.properties.configuration.ingress.fqdn}'
output storageAccountName string = storageAccount.name
output fileShareName string = fileShare.name
