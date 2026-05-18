using './main.bicep'

param appName = 'gelatai-factory'
param acrName = 'gelataiacr'
param containerImage = 'gelataiacr.azurecr.io/apifactory:latest'
param eventHubConnectionString = '' // pass via --parameters override or Key Vault
param eventHubName = 'esehusw3c5yeh7rri2h8grw4_eh'
