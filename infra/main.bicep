targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the the environment which is used to generate a short unique hash used in all resources.')
param environmentName string

@description('References application or service contact information from a Service or Asset Management database')
param serviceManagementReference string = ''

@description('Comma-separated list of client application IDs to pre-authorize for accessing the MCP API (optional)')
param preAuthorizedClientIds string = ''

@description('OAuth2 delegated permissions for App Service Authentication login flow')
param delegatedPermissions array = ['User.Read']

@minLength(1)
@description('Primary location for all resources & Flex Consumption Function App')
@metadata({
  azd: {
    type: 'location'
  }
})
param location string

param mcpServiceName string = ''
param apiUserAssignedIdentityName string = ''
param applicationInsightsName string = ''
param appServicePlanName string = ''
param logAnalyticsName string = ''
param resourceGroupName string = ''
param storageAccountName string = ''

@description('Base URL of the Ghost site (e.g. https://yourblog.ghost.io)')
param ghostApiUrl string

@description('Ghost Admin API key (from Ghost Admin > Integrations)')
@secure()
param ghostAdminApiKey string

@description('Ghost Admin API version')
param ghostApiVersion string = 'v5.0'

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = { 'azd-env-name': environmentName }
var functionAppName = !empty(mcpServiceName) ? mcpServiceName : '${abbrs.webSitesFunctions}mcp-${resourceToken}'
var deploymentStorageContainerName = 'app-package-${take(functionAppName, 32)}-${take(toLower(uniqueString(functionAppName, resourceToken)), 7)}'

// Convert comma-separated string to array for pre-authorized client IDs
var preAuthorizedClientIdsArray = !empty(preAuthorizedClientIds) ? map(split(preAuthorizedClientIds, ','), clientId => trim(clientId)) : []

// Organize resources in a resource group
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: !empty(resourceGroupName) ? resourceGroupName : '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

// User assigned managed identity to be used by the MCP function app to reach storage and other dependencies
module mcpUserAssignedIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.1' = {
  name: 'mcpUserAssignedIdentity'
  scope: rg
  params: {
    location: location
    tags: tags
    name: !empty(apiUserAssignedIdentityName) ? apiUserAssignedIdentityName : '${abbrs.managedIdentityUserAssignedIdentities}mcp-${resourceToken}'
  }
}

// Create an App Service Plan (Flex Consumption)
module appServicePlan 'br/public:avm/res/web/serverfarm:0.1.1' = {
  name: 'appserviceplan'
  scope: rg
  params: {
    name: !empty(appServicePlanName) ? appServicePlanName : '${abbrs.webServerFarms}${resourceToken}'
    sku: {
      name: 'FC1'
      tier: 'FlexConsumption'
    }
    reserved: true
    location: location
    tags: tags
  }
}

// Entra ID application registration for MCP authentication (with predictable hostname)
module entraApp 'app/entra.bicep' = {
  name: 'entraApp'
  scope: rg
  params: {
    appUniqueName: '${functionAppName}-app'
    appDisplayName: 'MCP Authorization App'
    serviceManagementReference: serviceManagementReference
    functionAppHostname: '${functionAppName}.azurewebsites.net'
    preAuthorizedClientIds: preAuthorizedClientIdsArray
    managedIdentityClientId: mcpUserAssignedIdentity.outputs.clientId
    managedIdentityPrincipalId: mcpUserAssignedIdentity.outputs.principalId
    tags: tags
  }
}

module mcp './app/mcp.bicep' = {
  name: 'mcp'
  scope: rg
  params: {
    name: functionAppName
    location: location
    tags: tags
    applicationInsightsName: monitoring.outputs.name
    appServicePlanId: appServicePlan.outputs.resourceId
    runtimeName: 'node'
    runtimeVersion: '22'
    storageAccountName: storage.outputs.name
    enableBlob: storageEndpointConfig.enableBlob
    enableQueue: storageEndpointConfig.enableQueue
    enableTable: storageEndpointConfig.enableTable
    deploymentStorageContainerName: deploymentStorageContainerName
    identityId: mcpUserAssignedIdentity.outputs.resourceId
    identityClientId: mcpUserAssignedIdentity.outputs.clientId
    preAuthorizedClientIds: preAuthorizedClientIdsArray
    appSettings: {
      AzureWebJobsFeatureFlags: 'EnableMcpCustomHandlerPreview'
      GHOST_API_URL: ghostApiUrl
      GHOST_ADMIN_API_KEY: ghostAdminApiKey
      GHOST_API_VERSION: ghostApiVersion
    }
    // No VNet integration - the Function App is publicly reachable over HTTPS.
    // Security is enforced by Easy Auth (Microsoft Entra ID) on the MCP endpoint.
    virtualNetworkSubnetId: ''
    authClientId: entraApp.outputs.applicationId
    authIdentifierUri: entraApp.outputs.identifierUri
    authExposedScopes: entraApp.outputs.exposedScopes
    authTenantId: tenant().tenantId
    delegatedPermissions: delegatedPermissions
  }
}

// Backing storage for Azure Functions (public access, managed identity auth, no shared keys)
module storage 'br/public:avm/res/storage/storage-account:0.8.3' = {
  name: 'storage'
  scope: rg
  params: {
    name: !empty(storageAccountName) ? storageAccountName : '${abbrs.storageStorageAccounts}${resourceToken}'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false // Disable local authentication methods as per policy
    dnsEndpointType: 'Standard'
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
    blobServices: {
      containers: [{ name: deploymentStorageContainerName }]
    }
    minimumTlsVersion: 'TLS1_2'
    location: location
    tags: tags
  }
}

// Define the configuration object locally to pass to the modules
var storageEndpointConfig = {
  enableBlob: true  // Required for AzureWebJobsStorage and .zip deployment
  enableQueue: false
  enableTable: false
  enableFiles: false
  allowUserIdentityPrincipal: false
}

// Consolidated Role Assignments
module rbac 'app/rbac.bicep' = {
  name: 'rbacAssignments'
  scope: rg
  params: {
    storageAccountName: storage.outputs.name
    appInsightsName: monitoring.outputs.name
    managedIdentityPrincipalId: mcpUserAssignedIdentity.outputs.principalId
    userIdentityPrincipalId: ''
    enableBlob: storageEndpointConfig.enableBlob
    enableQueue: storageEndpointConfig.enableQueue
    enableTable: storageEndpointConfig.enableTable
    allowUserIdentityPrincipal: storageEndpointConfig.allowUserIdentityPrincipal
  }
}

// Monitor application with Azure Monitor - Log Analytics and Application Insights
module logAnalytics 'br/public:avm/res/operational-insights/workspace:0.7.0' = {
  name: '${uniqueString(deployment().name, location)}-loganalytics'
  scope: rg
  params: {
    name: !empty(logAnalyticsName) ? logAnalyticsName : '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    location: location
    tags: tags
    dataRetention: 30
  }
}

module monitoring 'br/public:avm/res/insights/component:0.4.1' = {
  name: '${uniqueString(deployment().name, location)}-appinsights'
  scope: rg
  params: {
    name: !empty(applicationInsightsName) ? applicationInsightsName : '${abbrs.insightsComponents}${resourceToken}'
    location: location
    tags: tags
    workspaceResourceId: logAnalytics.outputs.resourceId
    disableLocalAuth: true
  }
}

// App outputs
output APPLICATIONINSIGHTS_CONNECTION_STRING string = monitoring.outputs.connectionString
output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output SERVICE_MCP_NAME string = mcp.outputs.SERVICE_MCP_NAME
output SERVICE_MCP_DEFAULT_HOSTNAME string = mcp.outputs.SERVICE_MCP_DEFAULT_HOSTNAME
output AZURE_FUNCTION_NAME string = mcp.outputs.SERVICE_MCP_NAME

// Entra App outputs (using the initial app for core properties)
output ENTRA_APPLICATION_ID string = entraApp.outputs.applicationId
output ENTRA_APPLICATION_OBJECT_ID string = entraApp.outputs.applicationObjectId
output ENTRA_SERVICE_PRINCIPAL_ID string = entraApp.outputs.servicePrincipalId
output ENTRA_IDENTIFIER_URI string = entraApp.outputs.identifierUri

// Authorization outputs
output AUTH_ENABLED bool = mcp.outputs.AUTH_ENABLED
output CONFIGURED_SCOPES string = mcp.outputs.CONFIGURED_SCOPES

// Pre-authorized applications
output PRE_AUTHORIZED_CLIENT_IDS string = preAuthorizedClientIds

// Entra App redirect URI outputs (using predictable hostname)
output CONFIGURED_REDIRECT_URIS array = entraApp.outputs.configuredRedirectUris
output AUTH_REDIRECT_URI string = entraApp.outputs.authRedirectUri
