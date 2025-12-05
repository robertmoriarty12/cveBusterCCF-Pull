# cveBuster CCF Connector - Deployment Instructions

## Prerequisites
- Access to Azure Sentinel workspace
- Azure Sentinel repository cloned locally
- PowerShell with Azure modules installed

## Step 1: Clone the Solution Repository

Navigate to your Azure Sentinel Solutions directory:

```powershell
cd C:\GitHub\Azure-Sentinel\Solutions
```

Clone the cveBuster CCF solution:

```powershell
git clone https://github.com/robertmoriarty12/cveBusterCCF-Pull.git
```

## Step 2: Generate the Solution Package

Navigate to the V3 solution creation tool:

```powershell
cd C:\GitHub\Azure-Sentinel\Tools\Create-Azure-Sentinel-Solution\V3
```

Run the solution package creation script:

```powershell
.\createSolutionV3.ps1
```

When prompted, enter the solution data folder path:

```
C:\GitHub\Azure-Sentinel\Solutions\cveBusterCCF-Pull\cveBuster\Data
```

The script will generate the deployment package in the `Package` folder.

## Step 3: Set Up the Mock API Server

The cveBuster solution includes a mock API server that simulates vulnerability data for testing purposes. This server should be deployed on an Azure VM running Ubuntu 24.04.

### Prerequisites for the VM

- Azure VM with Ubuntu 24.04
- Python 3.12+ installed
- Network connectivity from Azure Sentinel to the VM

### Connect to Your Ubuntu VM

```bash
ssh <username>@<vm-ip-address>
```

### Install Required System Packages

```bash
sudo apt update
sudo apt install python3-pip python3-venv git -y
```

### Clone the Repository on the VM

```bash
cd ~
git clone https://github.com/robertmoriarty12/cveBusterCCF-Pull.git
cd cveBusterCCF-Pull/Server
```

### Create a Python Virtual Environment

```bash
python3 -m venv venv
source venv/bin/activate
```

### Install Dependencies

```bash
pip install -r requirements.txt
```

### Generate Mock Vulnerability Data

Before starting the server, generate fresh mock vulnerability data:

```bash
python generate_data.py
```

This will create a `vulnerabilities.json` file with randomized vulnerability records and current timestamps. You can run this script anytime to refresh the data.

### Start the Flask Server

```bash
python app.py
```

The server will start on `http://0.0.0.0:5000` by default.

### Network Security Configuration

Configure your Azure VM Network Security Group (NSG) to allow inbound traffic on port 5000:

1. Navigate to your VM in the Azure Portal
2. Go to **Networking** > **Network settings**
3. Click **Create port rule** > **Inbound port rule**
4. Configure the rule:
   - **Source**: Any
   - **Source port ranges**: *
   - **Destination**: Any
   - **Service**: Custom
   - **Destination port ranges**: 5000
   - **Protocol**: TCP
   - **Action**: Allow
   - **Priority**: 1000
   - **Name**: Allow-Port-5000

### Verify Server is Running

Test the API endpoint from your local machine using PowerShell with the API key:

```powershell
Invoke-WebRequest -Uri "http://<vm-ip-address>:5000/api/vulnerabilities" -Method Get -Headers @{Authorization="Bearer cvebuster-demo-key-12345"}
```

Or use curl from the VM itself:

```bash
curl -H "Authorization: Bearer cvebuster-demo-key-12345" http://localhost:5000/api/vulnerabilities
```

You should receive a JSON response with mock vulnerability data.

**Note:** The default API key is `cvebuster-demo-key-12345`. For production use, change this in the `app.py` file before deployment.

### Configure as a System Service (Optional but Recommended)

To keep the server running persistently, create a systemd service:

```bash
sudo nano /etc/systemd/system/cvebuster-api.service
```

Add the following content:

```ini
[Unit]
Description=cveBuster Mock API Server
After=network.target

[Service]
Type=simple
User=<your-username>
WorkingDirectory=/home/<your-username>/cveBusterCCF-Pull/Server
Environment="PATH=/home/<your-username>/cveBusterCCF-Pull/Server/venv/bin"
ExecStart=/home/<your-username>/cveBusterCCF-Pull/Server/venv/bin/python app.py
Restart=always

[Install]
WantedBy=multi-user.target
```

Enable and start the service:

```bash
sudo systemctl daemon-reload
sudo systemctl enable cvebuster-api
sudo systemctl start cvebuster-api
sudo systemctl status cvebuster-api
```

### Server Endpoints

- `GET /api/vulnerabilities` - Returns paginated vulnerability data
- Supports pagination via `offset` and `limit` query parameters
- Example: `http://<vm-ip-address>:5000/api/vulnerabilities?offset=0&limit=100`

**Note:** For production use, replace the API endpoint in the connector configuration with your actual cveBuster API URL.

## Step 4: Deploy to Azure Sentinel

### Option A: Deploy via Azure Portal

1. Navigate to your Azure Sentinel workspace in the Azure Portal
2. Go to **Content Hub** > **Content Management**
3. Click **Import** and upload the generated package
4. Follow the deployment wizard to configure the connector

### Option B: Deploy via ARM Template

1. Locate the generated `mainTemplate.json` in the Package folder
2. Deploy using Azure CLI or PowerShell:

```powershell
# Using Azure PowerShell
New-AzResourceGroupDeployment `
  -ResourceGroupName "<your-resource-group>" `
  -TemplateFile ".\Package\mainTemplate.json" `
  -workspace "<your-sentinel-workspace-name>"
```

## Step 5: Configure the Connector

After deployment:

1. Navigate to **Data Connectors** in your Sentinel workspace
2. Find **cveBuster Vulnerability Scanner**
3. Configure the required parameters:
   - API Endpoint URL
   - Authentication credentials
   - Data Collection Endpoint (DCE)
   - Data Collection Rule (DCR)

## Verification

Verify data ingestion by running this KQL query in your Sentinel workspace:

```kql
cveBuster_Vulnerabilities_CL
| take 10
```

## Troubleshooting

- Check Azure Activity Log for deployment errors
- Verify DCE and DCR are properly configured
- Ensure API credentials are valid
- Check connector status in Data Connectors blade

## Support

For issues or questions, contact: support@yourcompany.com
