<#
.SYNOPSIS
    .
.DESCRIPTION
    .
.PARAMETER Mode
    Please select a scanning mode, which can be either Full.
    
.PARAMETER ProductionRun
    Default is $false, nothing will be changed. 
    Set to $True, will do assgin role.
    
.PARAMETER YesToAll
    Set to $true will skip all Confirm Box.
    
 .PARAMETER Login
    Default is $false, open a login box to Azure. Change to $Ture, will use the current Login session.
    
  .PARAMETER Log
    Set to $true  will genreate to log file for review.
    
.EXAMPLE
    C:\PS>.\AzureAgentAssignRole.ps1 -AppId "" -Mode Full -ProductionRun $false -Login $true -YesToAll $true -Log $true
    <Description of example>
.NOTES
    Author:Rury Chen rurychen@gmail.com:
    .\AzureAgentAssignRole.ps1 -AppId "" -Mode Full -ProductionRun $false -Login $true -Log $true -YesToAll $true
    Date: 2018-6-28
#>
[CmdletBinding(DefaultParameterSetName = "Mode")]
param(
  [Parameter(
    Mandatory = $true,
    ParameterSetName = "Mode",
    ValueFromPipeline = $true,
    ValueFromPipelineByPropertyName = $true,
    HelpMessage = "Select the Mode"
  )]
  [ValidateNotNullOrEmpty()]
  [string[]]
  [Alias('Please provide the Mode')]
  $Mode,#Mode
  [Parameter(
    Mandatory = $false
  )]
  $ProductionRun,
  [Parameter(
    Mandatory = $false
  )]
  $Login,
  [Parameter(
    Mandatory = $false
  )]
  $YesToAll,
  [Parameter(
    Mandatory = $false
  )]
  $Log,
  $AppId
)

Write-Host ""
if ([string]::IsNullOrEmpty($AppId)) {
  #$AppId = ""
  Write-Host "The Parameter -AppId cloud not be empty. "
  Write-Host "SAFE QUIT" -ForegroundColor Green
  exit
}

$RequireRoles = (
  "Reader",
  "Storage Account Key Operator Service Role"
)

# Add the Resouce name to here, all resouces start with following name will be ignore
$SkipResouceNameList = (
  "xxxx",
  "subscriptionName2"
)

function isNotSkip ($name) {
  foreach ($temp in $SkipResource) {

    if ($name.ToLower().StartsWith($temp)) {
      Write-Host (" Skip to Process: " + $name)
      WriteDebug (" Skip to Process: " + $name)
      return $false
    }

  }
  return $true
}
function ActivateDebug () {
  Add-Content -Path $LogfileActivated -Value "***************************************************************************************************"
  Add-Content -Path $LogfileActivated -Value "Started processing at [$([DateTime]::Now)]."
  Add-Content -Path $LogfileActivated -Value "***************************************************************************************************"
  Add-Content -Path $LogfileActivated -Value ""
  Write-Host "Debug Enabled writing to logfile: " $LogfileActivated
}

function WriteDebug ($msg) {
  if (isLog) {
    WriteDebugLogFile $msg
  }
}
function WriteDebugLogFile {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)] [string]$LineValue)
  process {
    Add-Content -Path $LogfileActivated -Value $LineValue
  }
}

function AssignRole ($appId,$subscription,$roleName) {

  $scope = "/subscriptions/" + $subscription.SubscriptionId
  Write-Host (" AssignRole '" + $roleName + "' for subscription: " + $subscription.Name)
  WriteDebug (" AssignRole '" + $roleName + "' for subscription: " + $subscription.Name)
  if ($ProductionRun -eq $true) {
    try {
      New-AzureRmRoleAssignment -ServicePrincipalName $appId -Scope $scope -RoleDefinitionName $roleName -ErrorAction Stop > $null
    }
    catch {
      WriteDebug $_.Exception.Message
      Write-Host ("Failed to assign : " + $_.Exception.Message)
    }
  }

}

function isLog () {
  return $Log -ne $null -and $Log -eq $true
}
Write-Host 'Log' $Log
if (isLog) {
  $date = (Get-Date).ToString("d-M-y-h.m.s")
  $logname = ("AzureAgentAssignRole-" + $date + ".log")
  #New-Item -Path $pwd.path -Value $LogName -ItemType File
  $LogfileActivated = $pwd.path + "\" + $LogName
  ActivateDebug
} #Activating DEBUG MODE

try {
  #Import-Module Azure.Storage
}
catch {
  Write-Host 'Modules NOT LOADED - EXITING'
  exit
}

#LOGIN TO TENANT
#clear
Write-Host ""
Write-Host ""
Write-Host ("-" * 90)
Write-Host ("             Welcome to the Foglight Azure Agent Role Assign") -ForegroundColor Cyan
Write-Host ("-" * 90)
Write-Host "This script using for Foglight Azure Agent Role Assign in your subscriptions" -ForegroundColor Yellow

Write-Host "Require following role: "
Write-Host ("-" * 90)
foreach ($temp in $RequireRoles) {
  Write-Host ($temp)

}

Write-Host ("-" * 90)


if (-not ($Login)) { Add-AzureRmAccount }

$selectedSubscriptions = New-Object System.Collections.ArrayList


$SkipResource = New-Object System.Collections.ArrayList

Write-Host "Skip add role under following subscriptions. (Edit SkipResouceNameList to add more item) " -ForegroundColor Yellow
Write-Host "----------"
foreach ($name in $SkipResouceNameList) {
  $SkipResource.Add($name.ToLower()) > $null
  Write-Host $name.ToLower() -ForegroundColor Red
}
Write-Host "----------"
WriteDebug ("Skip add role under following subscriptions. (Edit $SkipResouceNameList to add more item) :" + $SkipResource)


#GETTING A LIST OF SUBSCRIPTIONS
Write-Host "Getting the subscriptions, please wait..."

$Subscriptions = Get-AzureRmSubscription

foreach ($subscription in $Subscriptions) {
  #ask if it should be included
  $title = $subscription.Name
  $id = $subscription.SubscriptionId
  if ($YesToAll) {
    $selectedSubscriptions.Add($subscription) > $null
    WriteDebug ($id + " " + $subscription.Name)
  } else {
    $message = "Do you want this subscription to be added to the selection?"
    $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes",`
       "Adds the subscription to the script."
    $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No",`
       "Skips the subscription from scanning."
    $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes,$no)
    $result = $host.ui.PromptForChoice($title,$message,$options,0)
    switch ($result) {
      0 {
        $selectedSubscriptions.Add($subscription) > $null
        Write-Host ($subscription.Name + " has been added")
      }
      1 { Write-Host ($subscription.Name + " will be skipped")
      }
    }
  }
}

Write-Host ""
Write-Host "------------------------------------------------------"
Write-Host "Subscriptions selected:" -ForegroundColor Yellow

foreach ($entry in $selectedSubscriptions) { Write-Host " " + $entry.Name -ForegroundColor Yellow }

#Press P to continue.
if ($ProductionRun -eq $true) {
  Write-Host ""
  Write-Host "Set ProductionRun to false just print log. "
  $x = Read-Host 'Press any key to exit or press P to continue.'
  if ($x.ToUpper() -ne "P") {
    Write-Host "SAFE QUIT" -ForegroundColor Green
    exit
  }
  #Clear-Host
}

Write-Host (" Appid Is ( " + $AppId + " )")

#Assign Role
$i = 1;
foreach ($subscription in $selectedSubscriptions) {

  Write-Host $i ". Process subscription  " $subscription.Name
  if (isNotSkip $subscription.Name) {
    foreach ($roleName in $RequireRoles) {
      AssignRole $AppId $subscription $roleName
    }
  }
  $i++
  Write-Host ""
}

Write-Host ""
if ($ProductionRun -eq $False -or $ProductionRun -eq $null) {
  Write-Host "Nothing Changes. Please set ProductionRun to $true to make changes. Also You can edit SkipResouceNameList to add Skip Resouce if you want. " -ForegroundColor Cyan
}
Write-Host "Finished."

