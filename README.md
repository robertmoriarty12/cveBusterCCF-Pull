# Building a Microsoft Sentinel Codeless Connector (CCF) - Complete Lab Guide

> **Learn by doing**: This is a complete, working example that shows you how to build, package, and deploy a production-ready CCF connector for Microsoft Sentinel. You'll create a custom data connector that ingests vulnerability data into Sentinel using the Codeless Connector Framework.

---

## 📚 What You'll Learn

- **What CCF is** and why it's the modern way to build Sentinel connectors
- **How CCF works** - the architecture of Data Collection Rules (DCR), pollers, and custom tables
- **How to structure** a CCF solution following Microsoft's standards
- **How to package** your connector using Microsoft's official tooling
- **How to deploy** and test your connector in a real Sentinel workspace

---

## 🎯 What We're Building

**cveBuster Vulnerability Scanner Connector** - A real-world example that:
- Polls a REST API every 5 minutes for vulnerability data
- Uses API key authentication
- Ingests data into a custom Log Analytics table
- Transforms and maps 19 vulnerability fields (CVE IDs, CVSS scores, exploit status, etc.)
- Appears in the Sentinel Data Connectors gallery with a full UI

---

## 🏗️ Architecture Overview

### CCF Components (What You're Creating)

```
┌─────────────────────────────────────────────────────────────────┐
│                  Microsoft Sentinel Workspace                   │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │          Data Connector Gallery UI                        │  │
│  │  ┌────────────────────────────────────────────────────┐  │  │
│  │  │  cveBuster Vulnerability Scanner                   │  │  │
│  │  │  • API Endpoint Input                              │  │  │
│  │  │  • API Key Input                                   │  │  │
│  │  │  • Connect Button                                  │  │  │
│  │  └────────────────────────────────────────────────────┘  │  │
│  └──────────────────────────────────────────────────────────┘  │
│                           ↓                                     │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │         RestApiPoller (Runs every 5 minutes)            │  │
│  │  • Calls: http://YOUR-API:5000/api/vulnerabilities     │  │
│  │  • Auth: Authorization header with API key             │  │
│  │  • Extracts: $.data array from JSON response           │  │
│  └──────────────────────────────────────────────────────────┘  │
│                           ↓                                     │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │    Data Collection Rule (DCR)                           │  │
│  │  • Stream: Custom-cveBusterVulnerabilitiesStream       │  │
│  │  • Schema: 19 vulnerability fields                     │  │
│  │  • Transform: Adds TimeGenerated column                │  │
│  └──────────────────────────────────────────────────────────┘  │
│                           ↓                                     │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │    Custom Log Analytics Table                           │  │
│  │    cveBusterVulnerabilities_CL                         │  │
│  │  • 20 columns (TimeGenerated + 19 vuln fields)         │  │
│  │  • Query with KQL: cveBusterVulnerabilities_CL         │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### The 5 Required Files

| File | What It Does | Why You Need It |
|------|-------------|-----------------|
| **Connector Definition**<br>`cveBuster_connectorDefinition.json` | Defines the UI in Sentinel's Data Connectors gallery | Shows your connector to users, collects API endpoint/key inputs |
| **Poller Config**<br>`cveBuster_PollerConfig.json` | Configures REST API polling behavior | Tells Sentinel how often to call your API and how to authenticate |
| **DCR**<br>`cveBuster_DCR.json` | Data Collection Rule - schema and transformations | Defines what data fields to collect and how to transform them |
| **Table Schema**<br>`cveBuster_Table.json` | Log Analytics custom table definition | Creates the actual table in your workspace where data is stored |
| **Solution Metadata**<br>`Solution_cveBuster.json` | Package manifest | Tells the packaging tool what to include in your solution |

---

## 🚀 Lab Setup - Prerequisites

### What You'll Need

1. **Azure Subscription** with permissions to:
   - Create resource groups
   - Create Log Analytics workspaces
   - Deploy ARM templates
   - Enable Microsoft Sentinel

2. **Local Environment**:
   - Windows machine with PowerShell
   - Azure PowerShell module: `Install-Module -Name Az -Scope CurrentUser`
   - Git: `winget install Git.Git`

3. **GitHub Azure-Sentinel Repository**:
   ```powershell
   # Fork the repo on GitHub, then clone locally
   cd C:\
   mkdir GitHub
   cd GitHub
   git clone https://github.com/YOUR-USERNAME/Azure-Sentinel.git
   ```

4. **Demo API** (We'll use a simple Flask API):
   - An Ubuntu VM or local Python environment
   - IP address accessible from Azure (e.g., `20.84.144.179`)
   - API endpoint: `http://YOUR-IP:5000/api/vulnerabilities`
   - API key: `cvebuster-demo-key-12345`

---

## 📝 Step-by-Step Instructions

### Step 1: Understanding the File Structure

**What you're doing**: Creating the proper folder structure that Microsoft's packaging tool expects.

**Why**: The packaging tool (`createSolutionV3.ps1`) looks for a specific folder naming convention.

**Create this structure**:
```
C:\GitHub\Azure-Sentinel\Solutions\cveBuster\
├── Data\
│   └── Solution_cveBuster.json          # Package manifest
├── Data Connectors\
│   └── cveBusterVulnerabilitiesLogs_ccf\    # CCF naming: {Product}Logs_ccf
│       ├── cveBuster_connectorDefinition.json
│       ├── cveBuster_PollerConfig.json
│       ├── cveBuster_DCR.json
│       └── cveBuster_Table.json
├── SolutionMetadata.json                # Marketplace metadata
└── Package\                             # Generated by packaging tool
    └── mainTemplate.json                # This is what you deploy
```

**Run this**:
```powershell
# Create folder structure
New-Item -Path "C:\GitHub\Azure-Sentinel\Solutions\cveBuster\Data" -ItemType Directory -Force
New-Item -Path "C:\GitHub\Azure-Sentinel\Solutions\cveBuster\Data Connectors\cveBusterVulnerabilitiesLogs_ccf" -ItemType Directory -Force
New-Item -Path "C:\GitHub\Azure-Sentinel\Solutions\cveBuster\Package" -ItemType Directory -Force
```

**Key concepts**:
- `_ccf` suffix = tells Sentinel this is a Codeless Connector Framework connector
- Folder name `cveBusterVulnerabilitiesLogs_ccf` = becomes the stream name prefix
- All JSON files start with `cveBuster_` for consistency

---

### Step 2: Create the Solution Manifest

**What you're doing**: Creating `Solution_cveBuster.json` - the entry point for the packaging tool.

**Why**: This file tells the packaging tool what components are in your solution.

**Create file**: `C:\GitHub\Azure-Sentinel\Solutions\cveBuster\Data\Solution_cveBuster.json`

```json
{
  "Name": "cveBuster",
  "Author": "Your Company",
  "Logo": "<svg>...</svg>",
  "Description": "cveBuster Vulnerability Scanner data connector for Microsoft Sentinel",
  "BasePath": "C:\\GitHub\\Azure-Sentinel\\Solutions\\cveBuster",
  "Version": "1.0.0",
  "TemplateSpec": true,
  "Is1PConnector": false,
  "publisherId": "yourcompany",
  "offerId": "cvebuster-sentinel-solution",
  "providers": ["Your Company"],
  "categories": {
    "domains": ["Security - Vulnerability Management"]
  },
  "firstPublishDate": "2025-11-03",
  "support": {
    "name": "Your Company Support",
    "email": "support@yourcompany.com",
    "tier": "Partner",
    "link": "https://yourcompany.com/support"
  },
  "Data Connectors": [
    "Data Connectors/cveBusterVulnerabilitiesLogs_ccf/cveBuster_connectorDefinition.json"
  ]
}
```

**Key concepts**:
- `BasePath` = absolute path to your solution folder
- `Data Connectors` array = list of connector definition files to include
- `TemplateSpec: true` = use modern ARM template deployment method

---

### Step 3: Create the Connector Definition (UI)

**What you're doing**: Defining how your connector appears in Sentinel's Data Connectors gallery.

**Why**: This creates the user interface - the form users fill out to connect to your API.

**Create file**: `C:\GitHub\Azure-Sentinel\Solutions\cveBuster\Data Connectors\cveBusterVulnerabilitiesLogs_ccf\cveBuster_connectorDefinition.json`

```json
{
  "type": "Microsoft.SecurityInsights/dataConnectorDefinitions",
  "apiVersion": "2022-09-01-preview",
  "name": "cveBusterVulnerabilitiesConnectorDefinition",
  "kind": "Customizable",
  "properties": {
    "connectorUiConfig": {
      "id": "cveBusterVulnerabilitiesConnector",
      "title": "cveBuster Vulnerability Scanner",
      "publisher": "Your Company",
      "descriptionMarkdown": "Ingests vulnerability scan data from cveBuster API",
      "graphQueriesTableName": "cveBusterVulnerabilities_CL",
      "graphQueries": [
        {
          "metricName": "Total vulnerability records",
          "legend": "cveBuster Vulnerabilities",
          "baseQuery": "{{graphQueriesTableName}}"
        }
      ],
      "dataTypes": [
        {
          "name": "{{graphQueriesTableName}}",
          "lastDataReceivedQuery": "{{graphQueriesTableName}}\n| summarize Time = max(TimeGenerated)\n| where isnotempty(Time)"
        }
      ],
      "connectivityCriteria": [
        {
          "type": "HasDataConnectors",
          "value": []
        }
      ],
      "availability": {
        "status": 1,
        "isPreview": false
      },
      "permissions": {
        "resourceProvider": [
          {
            "provider": "Microsoft.OperationalInsights/workspaces",
            "permissionsDisplayText": "Read and Write permissions are required.",
            "providerDisplayName": "Workspace",
            "scope": "Workspace",
            "requiredPermissions": {
              "write": true,
              "read": true,
              "delete": true
            }
          }
        ],
        "customs": [
          {
            "name": "cveBuster API Access",
            "description": "An API key with read access to the cveBuster vulnerability scanning API is required."
          }
        ]
      },
      "instructionSteps": [
        {
          "title": "Configure Connection",
          "description": "Enter your cveBuster API endpoint and authentication key. The connector will poll the API every 5 minutes.",
          "instructions": [
            {
              "type": "Textbox",
              "parameters": {
                "label": "API Endpoint URL",
                "placeholder": "http://20.84.144.179:5000/api/vulnerabilities",
                "name": "apiEndpoint"
              }
            },
            {
              "type": "Textbox",
              "parameters": {
                "label": "API Key",
                "placeholder": "Enter your API key",
                "name": "apiKey"
              }
            },
            {
              "type": "ConnectionToggleButton",
              "parameters": {}
            }
          ]
        }
      ]
    }
  }
}
```

**Key concepts**:
- `id` = unique connector ID (referenced by PollerConfig)
- `graphQueriesTableName` = the Log Analytics table name
- `instructionSteps` = the form inputs users see (API endpoint, API key, Connect button)
- `{{graphQueriesTableName}}` = placeholder replaced with actual table name

---

### Step 4: Create the Poller Configuration

**What you're doing**: Configuring how Sentinel polls your REST API.

**Why**: This tells Sentinel when to call your API, how to authenticate, and where to send the data.

**Create file**: `C:\GitHub\Azure-Sentinel\Solutions\cveBuster\Data Connectors\cveBusterVulnerabilitiesLogs_ccf\cveBuster_PollerConfig.json`

```json
[
  {
    "type": "Microsoft.SecurityInsights/dataConnectors",
    "apiVersion": "2022-10-01-preview",
    "name": "cveBusterVulnerabilitiesPoller",
    "kind": "RestApiPoller",
    "properties": {
      "connectorDefinitionName": "cveBusterVulnerabilitiesConnector",
      "dataType": "cveBusterVulnerabilities_CL",
      "dcrConfig": {
        "streamName": "Custom-cveBusterVulnerabilitiesStream",
        "dataCollectionEndpoint": "[[parameters('dcrConfig').dataCollectionEndpoint]",
        "dataCollectionRuleImmutableId": "[[parameters('dcrConfig').dataCollectionRuleImmutableId]"
      },
      "auth": {
        "type": "APIKey",
        "ApiKey": "[[parameters('apiKey')]",
        "ApiKeyName": "Authorization"
      },
      "request": {
        "apiEndpoint": "[[parameters('apiEndpoint')]",
        "rateLimitQPS": 10,
        "queryWindowInMin": 5,
        "httpMethod": "GET",
        "queryTimeFormat": "yyyy-MM-ddTHH:mm:ssZ",
        "retryCount": 3,
        "timeoutInSeconds": 60,
        "headers": {
          "Accept": "application/json",
          "User-Agent": "cveBuster-Sentinel-Connector/1.0"
        },
        "queryParameters": {}
      },
      "response": {
        "eventsJsonPaths": [
          "$.data"
        ],
        "format": "json"
      }
    }
  }
]
```

**Key concepts**:
- `connectorDefinitionName` = MUST match the `id` from connectorDefinition.json
- `streamName` = MUST match the DCR's stream declaration
- `queryWindowInMin: 5` = poll every 5 minutes
- `[[parameters('apiKey')]` = double brackets = ARM template parameter syntax
- `eventsJsonPaths: ["$.data"]` = extract array from `{"data": [...]}` response
- `ApiKeyName: "Authorization"` = HTTP header name to use

---

### Step 5: Create the Data Collection Rule (DCR)

**What you're doing**: Defining the data schema and transformations.

**Why**: This tells Sentinel what fields to expect and how to map them to your Log Analytics table.

**Create file**: `C:\GitHub\Azure-Sentinel\Solutions\cveBuster\Data Connectors\cveBusterVulnerabilitiesLogs_ccf\cveBuster_DCR.json`

```json
[
  {
    "name": "cveBusterVulnerabilitiesDCR",
    "location": "[parameters('workspace-location')]",
    "apiVersion": "2021-09-01-preview",
    "type": "Microsoft.Insights/dataCollectionRules",
    "properties": {
      "dataCollectionEndpointId": "{{dataCollectionEndpointId}}",
      "streamDeclarations": {
        "Custom-cveBusterVulnerabilitiesStream": {
          "columns": [
            {"name": "MachineName", "type": "string"},
            {"name": "HostId", "type": "string"},
            {"name": "IPAddress", "type": "string"},
            {"name": "OSFamily", "type": "string"},
            {"name": "Application", "type": "string"},
            {"name": "AppFilePath", "type": "string"},
            {"name": "VulnId", "type": "string"},
            {"name": "VulnTitle", "type": "string"},
            {"name": "Severity", "type": "string"},
            {"name": "CVSS", "type": "real"},
            {"name": "ExploitAvailable", "type": "boolean"},
            {"name": "ExploitedInWild", "type": "boolean"},
            {"name": "PatchAvailable", "type": "boolean"},
            {"name": "FirstSeen", "type": "datetime"},
            {"name": "LastSeen", "type": "datetime"},
            {"name": "LastScanTime", "type": "datetime"},
            {"name": "AssetCriticality", "type": "string"},
            {"name": "BusinessOwner", "type": "string"},
            {"name": "Source", "type": "string"}
          ]
        }
      },
      "destinations": {
        "logAnalytics": [
          {
            "workspaceResourceId": "{{workspaceResourceId}}",
            "name": "clv2ws1"
          }
        ]
      },
      "dataFlows": [
        {
          "streams": ["Custom-cveBusterVulnerabilitiesStream"],
          "destinations": ["clv2ws1"],
          "transformKql": "source | extend TimeGenerated = now()",
          "outputStream": "Custom-cveBusterVulnerabilities_CL"
        }
      ]
    }
  }
]
```

**Key concepts**:
- `location: "[parameters('workspace-location')]"` = CRITICAL - sets region for DCR (use single brackets for ARM parameter)
- `streamDeclarations` = defines the incoming data schema (19 fields from API)
- `transformKql` = KQL query to transform data (adds TimeGenerated timestamp)
- `outputStream` = MUST match the table name with `Custom-` prefix
- Field types: `string`, `real` (float), `boolean`, `datetime`

---

### Step 6: Create the Table Schema

**What you're doing**: Defining the Log Analytics custom table.

**Why**: This creates the actual table in your workspace where vulnerability data is stored.

**Create file**: `C:\GitHub\Azure-Sentinel\Solutions\cveBuster\Data Connectors\cveBusterVulnerabilitiesLogs_ccf\cveBuster_Table.json`

```json
{
  "properties": {
    "schema": {
      "name": "cveBusterVulnerabilities_CL",
      "tableType": "CustomLog",
      "tableSubType": "DataCollectionRuleBased",
      "columns": [
        {"name": "TimeGenerated", "type": "datetime", "isDefaultDisplay": true, "isHidden": false},
        {"name": "MachineName", "type": "string", "isDefaultDisplay": true},
        {"name": "HostId", "type": "string"},
        {"name": "IPAddress", "type": "string", "isDefaultDisplay": true},
        {"name": "OSFamily", "type": "string"},
        {"name": "Application", "type": "string", "isDefaultDisplay": true},
        {"name": "AppFilePath", "type": "string"},
        {"name": "VulnId", "type": "string", "isDefaultDisplay": true},
        {"name": "VulnTitle", "type": "string", "isDefaultDisplay": true},
        {"name": "Severity", "type": "string", "isDefaultDisplay": true},
        {"name": "CVSS", "type": "real", "isDefaultDisplay": true},
        {"name": "ExploitAvailable", "type": "boolean"},
        {"name": "ExploitedInWild", "type": "boolean", "isDefaultDisplay": true},
        {"name": "PatchAvailable", "type": "boolean"},
        {"name": "FirstSeen", "type": "datetime"},
        {"name": "LastSeen", "type": "datetime"},
        {"name": "LastScanTime", "type": "datetime"},
        {"name": "AssetCriticality", "type": "string"},
        {"name": "BusinessOwner", "type": "string"},
        {"name": "Source", "type": "string"}
      ]
    }
  }
}
```

**Key concepts**:
- `_CL` suffix = "Custom Log" naming convention
- `isDefaultDisplay: true` = shows in default Log Analytics query results
- Schema MUST match DCR's streamDeclarations + TimeGenerated
- 20 total columns: TimeGenerated + 19 vulnerability fields

---

### Step 7: Create Solution Metadata

**What you're doing**: Adding marketplace metadata (optional but recommended).

**Why**: If you want to publish to Content Hub, this provides the metadata.

**Create file**: `C:\GitHub\Azure-Sentinel\Solutions\cveBuster\SolutionMetadata.json`

```json
{
  "publisherId": "yourcompany",
  "offerId": "cvebuster-sentinel-solution",
  "firstPublishDate": "2025-11-03",
  "providers": ["Your Company"],
  "categories": {
    "domains": ["Security - Vulnerability Management", "Security - Threat Protection"]
  },
  "support": {
    "name": "Your Company Support",
    "email": "support@yourcompany.com",
    "tier": "Partner",
    "link": "https://yourcompany.com/support"
  }
}
```

---

### Step 8: Package Your Solution

**What you're doing**: Running Microsoft's packaging tool to generate the ARM template.

**Why**: The packaging tool converts your 5 JSON files into a single `mainTemplate.json` ARM template that can be deployed.

**Run this**:
```powershell
# Navigate to packaging tool
cd C:\GitHub\Azure-Sentinel\Tools\Create-Azure-Sentinel-Solution\V3

# Run the packaging tool (it will prompt for the path)
.\createSolutionV3.ps1

# When prompted, enter:
# C:\GitHub\Azure-Sentinel\Solutions\cveBuster\Data
```

**What happens**:
1. Tool reads `Solution_cveBuster.json`
2. Tool finds all referenced connector files
3. Tool validates JSON structure
4. Tool generates ARM template at: `C:\GitHub\Azure-Sentinel\Solutions\cveBuster\Package\mainTemplate.json`

**Success looks like**:
```
************Validating if Package Json files are valid or not***************
File C:\GitHub\Azure-Sentinel\Solutions\cveBuster\Package\createUiDefinition.json is a valid Json file!
File C:\GitHub\Azure-Sentinel\Solutions\cveBuster\Package\mainTemplate.json is a valid Json file!
File C:\GitHub\Azure-Sentinel\Solutions\cveBuster\Package\testParameters.json is a valid Json file!
```

---

### Step 9: Deploy to Azure

**What you're doing**: Creating a Sentinel workspace and deploying your connector.

**Why**: This is where you actually install your connector into a live Sentinel environment.

**Run this**:
```powershell
# Variables (customize these)
$rgName = "sentineltesting"
$wsName = "sentineltesting"
$location = "Central US"
$subscriptionId = "YOUR-SUBSCRIPTION-ID"

# 1. Create resource group
New-AzResourceGroup -Name $rgName -Location $location

# 2. Create Log Analytics workspace
New-AzOperationalInsightsWorkspace `
    -ResourceGroupName $rgName `
    -Name $wsName `
    -Location $location `
    -Sku "PerGB2018"

# 3. Enable Microsoft Sentinel
$body = @{ properties = @{} } | ConvertTo-Json
Invoke-AzRestMethod `
    -Method PUT `
    -Path "/subscriptions/$subscriptionId/resourceGroups/$rgName/providers/Microsoft.OperationalInsights/workspaces/$wsName/providers/Microsoft.SecurityInsights/onboardingStates/default?api-version=2024-03-01" `
    -Payload $body

# 4. Deploy the solution
New-AzResourceGroupDeployment `
    -ResourceGroupName $rgName `
    -TemplateFile "C:\GitHub\Azure-Sentinel\Solutions\cveBuster\Package\mainTemplate.json" `
    -workspace $wsName `
    -TemplateParameterObject @{'workspace-location'=$location.ToLower().Replace(' ','')}
```

**What happens**:
1. Creates resource group
2. Creates Log Analytics workspace
3. Enables Sentinel on the workspace
4. Deploys your connector (creates DCR, table, poller, connector definition)

**Key parameter**: `workspace-location` MUST be lowercase, no spaces (e.g., `centralus`)

---

### Step 10: Configure and Test

**What you're doing**: Connecting your API and verifying data flow.

**Why**: This activates the poller and starts ingesting data.

#### In Azure Portal:

1. Navigate to: **Microsoft Sentinel** → Your workspace → **Data connectors**
2. Find: **cveBuster Vulnerability Scanner**
3. Click **Open connector page**
4. Enter:
   - **API Endpoint URL**: `http://20.84.144.179:5000/api/vulnerabilities`
   - **API Key**: `cvebuster-demo-key-12345`
5. Click **Connect**

**Success**: You should see "Connected" status

#### Verify Data Ingestion:

Wait 5-10 minutes for the first poll, then run this KQL query:

```kql
cveBusterVulnerabilities_CL
| take 10
```

**You should see**: 10 vulnerability records with all 20 columns populated

#### Check Specific Data:

```kql
// Critical vulnerabilities with active exploits
cveBusterVulnerabilities_CL
| where Severity == "Critical" and ExploitedInWild == true
| project TimeGenerated, MachineName, VulnId, VulnTitle, CVSS
| order by TimeGenerated desc
```

---

## 🔍 Troubleshooting

### Issue: Location error when connecting

**Error**: `"The location property is required for this definition"`

**Fix**: The DCR MUST have `"location": "[parameters('workspace-location')]"` and you MUST pass the parameter when deploying:
```powershell
-TemplateParameterObject @{'workspace-location'='centralus'}
```

### Issue: 401 Unauthorized from API

**Error**: `Call failed with status code 401 (UNAUTHORIZED)`

**Fix**: Check that your PollerConfig has:
```json
"auth": {
  "type": "APIKey",
  "ApiKey": "[[parameters('apiKey')]",
  "ApiKeyName": "Authorization"
}
```
**NOT**: `"ApiKeyIdentifier"` field (that's for OAuth, not API keys)

### Issue: Invalid paging type

**Error**: `Field 'pagingType' contains an invalid value 'None'`

**Fix**: Remove the `paging` section entirely from PollerConfig if your API doesn't paginate. Only use paging if you need `NextPageToken` or `LinkHeader` pagination.

### Issue: Connector doesn't appear in gallery

**Fix**: 
1. Check deployment succeeded: `ProvisioningState: Succeeded`
2. Refresh browser (Ctrl+F5)
3. If still missing, redeploy to a NEW workspace (connector definitions are cached)

---

## 📊 Understanding Your Data

### Table Schema (20 columns)

| Column | Type | Description |
|--------|------|-------------|
| `TimeGenerated` | datetime | When data was ingested (added by DCR) |
| `MachineName` | string | Hostname of vulnerable system |
| `HostId` | string | Unique host identifier (GUID) |
| `IPAddress` | string | IP address |
| `OSFamily` | string | Operating system (e.g., "Ubuntu 20.04") |
| `Application` | string | Vulnerable application name |
| `AppFilePath` | string | Path to vulnerable binary |
| `VulnId` | string | CVE identifier (e.g., "CVE-2021-44228") |
| `VulnTitle` | string | Human-readable vulnerability name |
| `Severity` | string | Critical/High/Medium/Low |
| `CVSS` | real | CVSS score (0.0 to 10.0) |
| `ExploitAvailable` | boolean | Known exploit exists |
| `ExploitedInWild` | boolean | Actively exploited in the wild |
| `PatchAvailable` | boolean | Vendor patch available |
| `FirstSeen` | datetime | When vulnerability was first detected |
| `LastSeen` | datetime | Most recent detection |
| `LastScanTime` | datetime | Last scan timestamp |
| `AssetCriticality` | string | Business criticality (High/Medium/Low) |
| `BusinessOwner` | string | Team responsible for asset |
| `Source` | string | Data source identifier |

### Sample KQL Queries

**Vulnerability count by severity**:
```kql
cveBusterVulnerabilities_CL
| summarize Count=count() by Severity
| render piechart
```

**Top 10 machines with most vulnerabilities**:
```kql
cveBusterVulnerabilities_CL
| summarize VulnCount=count() by MachineName
| top 10 by VulnCount desc
```

**Actively exploited CVEs**:
```kql
cveBusterVulnerabilities_CL
| where ExploitedInWild == true
| summarize Machines=dcount(MachineName) by VulnId, VulnTitle, CVSS
| order by CVSS desc
```

---

## 🎓 Key Learnings & Best Practices

### 1. **CCF vs Traditional Connectors**

| Aspect | Traditional (Python/Logic Apps) | CCF (Codeless) |
|--------|--------------------------------|----------------|
| Code required | Yes - Python/PowerShell | No - JSON config only |
| Deployment | Custom VM/container | Managed by Sentinel |
| Maintenance | You manage infrastructure | Microsoft manages |
| Scaling | Manual | Automatic |
| Authentication | Custom implementation | Built-in API key/OAuth |

### 2. **Naming Conventions Matter**

- Folder: `{ProductName}Logs_ccf` suffix
- Files: `{SolutionName}_connectorDefinition.json` pattern
- Table: `{TableName}_CL` suffix (Custom Log)
- Stream: `Custom-{StreamName}` prefix
- Output stream: `Custom-{TableName}` (matches table with `Custom-` prefix)

### 3. **Parameter Syntax**

- ARM template parameters: `[parameters('paramName')]` (single brackets)
- CCF placeholders in source files: `{{placeholder}}` (double curly braces)
- Poller runtime parameters: `[[parameters('paramName')]` (double brackets)

### 4. **The Magic Matching**

These MUST match for CCF to work:

```
connectorDefinition.json:
  "id": "cveBusterVulnerabilitiesConnector"
              ↓
PollerConfig.json:
  "connectorDefinitionName": "cveBusterVulnerabilitiesConnector"

PollerConfig.json:
  "streamName": "Custom-cveBusterVulnerabilitiesStream"
              ↓
DCR.json:
  "streamDeclarations": {
    "Custom-cveBusterVulnerabilitiesStream": { ... }
  }

DCR.json:
  "outputStream": "Custom-cveBusterVulnerabilities_CL"
              ↓
Table.json:
  "name": "cveBusterVulnerabilities_CL"
```

### 5. **Testing Strategy**

1. **Test API manually first** with curl/Postman
2. **Deploy to new workspace** for each iteration (avoid caching issues)
3. **Check deployment output** for `ProvisioningState: Succeeded`
4. **Wait 5-10 minutes** after connecting before checking for data
5. **Use KQL to verify** - don't just trust the UI graph

---

## 🚀 Next Steps

### Enhance Your Connector

1. **Add more data types**: Create multiple pollers for different endpoints
2. **Implement paging**: If your API returns > 1000 records
3. **Add rate limiting**: Adjust `rateLimitQPS` based on API limits
4. **Create workbooks**: Visualize vulnerability data
5. **Build analytics rules**: Alert on critical vulnerabilities
6. **Add playbooks**: Automate remediation workflows

### Publish Your Solution

1. **Test thoroughly**: Multiple workspaces, different scenarios
2. **Write comprehensive docs**: User guide, troubleshooting
3. **Submit to Content Hub**: Follow Microsoft's submission process
4. **Maintain**: Update for API changes, new features

---

## 📚 Additional Resources

- **Microsoft CCF Documentation**: https://learn.microsoft.com/en-us/azure/sentinel/create-codeless-connector
- **Azure-Sentinel GitHub**: https://github.com/Azure/Azure-Sentinel
- **SentinelOne Example**: Reference connector in Azure-Sentinel repo
- **ARM Template Reference**: https://learn.microsoft.com/en-us/azure/templates/
- **KQL Reference**: https://learn.microsoft.com/en-us/azure/data-explorer/kusto/query/

---

## ❓ FAQ

**Q: Can I use this for production?**
A: Yes! This is a production-ready pattern. Just replace the demo API with your real API.

**Q: Do I need to redeploy when I update my API?**
A: No. The poller config stays the same as long as your API contract (endpoint, auth, response format) doesn't change.

**Q: Can I have multiple pollers in one solution?**
A: Yes! Add more entries to the PollerConfig array, each with its own endpoint and stream.

**Q: How do I update an existing connector?**
A: Make your changes, increment the version in Solution.json, repackage, and redeploy.

**Q: Why does my data show up late?**
A: Pollers run every `queryWindowInMin` (5 min default), plus Sentinel ingestion can take 5-10 min. Total delay: ~10-15 minutes.

---

## 🎯 Summary

You've learned how to:
- ✅ Structure a CCF solution following Microsoft's standards
- ✅ Create 5 required JSON files (Definition, Poller, DCR, Table, Solution)
- ✅ Package with Microsoft's official tooling
- ✅ Deploy to a Sentinel workspace
- ✅ Configure and test data ingestion
- ✅ Query vulnerability data with KQL

**This template works for ANY REST API** - just modify the schema and endpoints!

---

**Built by**: [Your Name]  
**Date**: November 2025  
**License**: MIT  
**Contributions**: Welcome! Open issues/PRs on GitHub
