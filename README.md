# AzureAgentAssignRole
Auto  Assign Azure Role  for Application. 
Default roles is:
"Reader",
"Storage Account Key Operator Service Role"

# Steps 1. Install AzureRM PowerShell 5.0.0.
Ref Guide:
https://docs.microsoft.com/en-us/powershell/azure/install-azurerm-ps?view=azurermps-5.0.0

Install the Azure Resource Manager modules from the PowerShell Gallery
```ps
Install-Module AzureRM -AllowClobber
```
Some times it failed with  "gives error Install-Module A parameter cannot be found that matches parameter name AllowClobber".

Note that AllowClobber is only available on PS 5  and later.
We could try this.
```ps
find-module azurerm | Install-Module
```

# Steps 2. Load the AzureRM module
```ps
Import-Module AzureRM
```

# Steps 3. Checking the version of Azure PowerShell
```ps
Get-Module AzureRM -list | Select-Object Name,Version,Path
```

# Step 4. Download the script AzureAgentAssignRole.ps1 , and run following command in the PowerShell console.
```ps
.\AzureAgentAssignRole.ps1 -AppId "xxx-xxx-xxx-xx" -Mode Full -ProductionRun $false -Login $true -YesToAll $true -Log $true
```
Note: Appid is Application ID under Azure Portal(portal.azure.com):
Azure Active Directory -> App registrations -> Select One of the APP.

# Step 5. Change the ProductionRun to $true to do changes.
```ps
.\AzureAgentAssignRole.ps1 -AppId "xxx-xxx-xxx-xx" -Mode Full -ProductionRun $true -Login $true -YesToAll $true -Log $true
```
