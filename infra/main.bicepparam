using './main.bicep'

param appName = 'gelatai-factory'
param containerImage = 'yourregistry.azurecr.io/apifactory:latest'
param eventHubConnectionString = ''
param eventHubName = ''
