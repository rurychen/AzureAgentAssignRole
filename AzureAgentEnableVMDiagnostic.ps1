<#
.SYNOPSIS
    .
.DESCRIPTION
    .This AzureRM Script is used to enable VM Diagnostic for Linux and Windows VM with multithreading.

.PARAMETER ProductionRun
    Default is $false, nothing will be changed and just print the mockup result.
    Set to $True, will do enable VM Diagnostic.

.PARAMETER cleanup
    Default is $false, it means it will enable VM Diagnostic.
    Set to $True, it will clean up the VM Diagnostic.

.PARAMETER subscriptionId
    Specify the subscription ID. Default is empty and will process on all Subscriptions.

.PARAMETER targetRsgName
    Specify the Resource Group Name, it will process on the VMs which under this Resource Group Name. Default is empty and will process on VMs under the Subscriptions.

.PARAMETER targetVmName
    Specify the VM Name, it will process on the VMs which are the same VM Name. Default is empty and will process on VMs under the Subscriptions.

.EXAMPLE
   Upload the AzureAgentEnableVMDiagnostic.ps1 run it.
        PS Azure:\> .\enable-vm-diagnostic.ps1 -cleanup $false -ProductionRun $false
Note:
- Just testing script by setting the parameter:  -ProductionRun $false
- Clean up the VM diagnostic by setting parameter:   -cleanup $true
- This script is running with multithreading. If there contains large number of VMs, please increase the parameter $ThreadCount from default value 20 to a suitable value.

.NOTES
    Author:Rury Chen rurychen@gmail.com
    Create Date: 2019-09-15
    Last update: 2019-09-17
#>

param(

    [Parameter(Mandatory=$False)]
    [string]
    $subscriptionId,

    [Parameter(Mandatory=$False)]
    [string]
    $targetRsgName,

    [Parameter(Mandatory=$False)]
    [string]
    $targetVmName,

    $cleanup,
    $ProductionRun


)


#$subscriptionId = "XXXXX"
#$targetRsgName = "RuryTest"
#$targetVmName = "rurytestlinux"


#$diagnosticStorageAccountName = "vmdiagnostic20190906"

#Max length for the name of stroage account Prefix should less than 11 ( Azure limit the name lenth less than 24, we will create random name for the subfix)
$storageNamePrefix = "autovmdiag"

$storageType = "Standard_LRS"
$deployExtensionLogDir = split-path -parent $MyInvocation.MyCommand.Definition
#$ProductionRun = $true
$ThreadCount = 20

#$cleanup = @true


#-------------script start !----------

if ([string]::IsNullOrEmpty($ProductionRun)) {
    $ProductionRun = $False;
}

if ([string]::IsNullOrEmpty($cleanup)) {
    $cleanup = $False;
}

if($ThreadCount -le 1)
{
    $ThreadCount = 1
}

if ([string]::IsNullOrEmpty($storageNamePrefix) -and $storageNamePrefix -gt 11) {
    $storageNamePrefix = $storageNamePrefix.Substring(0,11)
}


Write-Host "Clean up is " $cleanup


function Enable-Diagnostics-multi-thread
{
    param(
        $vmList
    )

    #Write-Host "vmList is " $vmList.Count
    #Write-Host "diagnosticStorageAccountName " $diagnosticStorageAccountName
    #Write-Host "storageType =" $storageType
    #Write-Host "storageNamePrefix =" $storageNamePrefix
    #Write-Host "deployExtensionLogDir =" $deployExtensionLogDir
    #Write-Host "ProductionRun =" $ProductionRun
    #Write-Host "cleanup =" $cleanup

    #$vmList = Get-AzureRmVM -ResourceGroupName "RuryTest"
    #$vmList = Get-AzureRmVM

    $throttleLimit = $ThreadCount
    $SessionState = [system.management.automation.runspaces.initialsessionstate]::CreateDefault()
    $Pool = [runspacefactory]::CreateRunspacePool(1, $throttleLimit, $SessionState, $Host)
    $Pool.Open()


    $ScriptBlock = {
        param($vm,
            $diagnosticStorageAccountName,
            $storageType,
            $storageNamePrefix,
            $deployExtensionLogDir,
            $ProductionRun ,
            $cleanup
        )


        function Test-FUN
        {
            Write-Host "Test-FUN "
        }

        function Get-UniqueString ([string]$id, $length=13)
        {
            $hashArray = (new-object System.Security.Cryptography.SHA512Managed).ComputeHash($id.ToCharArray())
            -join ($hashArray[1..$length] | ForEach-Object { [char]($_ % 26 + [byte][char]'a') })
        }

        function Create-RandomStorageAccount($rsgName,$rsgLocation,$storageName, $vmName){
            Write-Host "#$vmName" "Get-AzureRmStorageAccount -ResourceGroupName" $rsgName  "-AccountName" $storageName
            $storageAccount = Get-AzureRmStorageAccount -ResourceGroupName $rsgName -AccountName $storageName
            if($storageAccount){
                Write-Host "#$vmName" "Use the exist StorageAccount " $storageName
                return $storageAccount
            }else{
                Write-Host "#$vmName" "New-AzureRmStorageAccount -ResourceGroupName $rsgName -AccountName $storageName -Location $rsgLocation -Type $storageType"
                $storageAccount = New-AzureRmStorageAccount -ResourceGroupName $rsgName -AccountName $storageName -Location $rsgLocation -Type $storageType
                return $storageAccount
            }
        }

        function Get-RandomStorageName{
            param($id)
            #$randomResult = ""
            #for($i = 0;$i -lt 10;$i++){
            #    $random = Get-Random -Maximum 9 -Minimum 0
            #    $randomResult+=$random
            #}
            $randomResult = Get-UniqueString -id $id
            $storageName = $storageNamePrefix+$randomResult
            return $storageName

        }

        # if the extension has existed, just skip
        function Enable-LinuxDiagnosticsExtension($vm,$rsg,$rsgName,$rsgLocation,$vmId,$vmName, $storageName ){
            $extensionType="LinuxDiagnostic"
            $extensionName = "LinuxDiagnostic"

            Write-Host "#$vmName" "Get-AzureRmVM -Name $vmName -ResourceGroupName $rsgName"
            $vm = Get-AzureRmVM -Name $vmName -ResourceGroupName $rsgName
            $extension = $vm.Extensions | Where-Object -Property 'VirtualMachineExtensionType' -eq $extensionType
            Write-Host "#$vmName" " Extension state " $extension.ProvisioningState
            if( $extension -and $extension.ProvisioningState -eq 'Succeeded'){
                if ($cleanup -eq $true) {
                    Write-Host "#$vmName" "Remove-AzureRmVMExtension $rsgName -VMName $vmName -Name $extensionName -Force"
                    if ($ProductionRun -eq $true)
                    {
                        $Response = Remove-AzureRmVMExtension -ResourceGroupName $rsgName -VMName $vmName -Name $extensionName -Force
                        return "Remove Extension Done - Linux. " + $Response.StatusCode
                    }
                    else
                    {
                        return "Mockup Remove"
                    }
                }else{
                    Write-Host "#$vmName" " just skip,due to diagnostics extension had been installed in VM before,you can update the diagnostics settings via portal or powershell cmdlets by yourself."
                    return "Skip due to diagnostics extension had been installed"
                }

            }elseif ($cleanup -eq $true) {
                Write-Host "#$vmName" "Not need to clean up Extension for $rsgName -VMName $vmName -Name $extensionName"
                return "No Extension need cleanup"
            }

            Write-Host "#$vmName" " use storageName:" $storageName
            $storageKey = ""
            if ($ProductionRun -eq $true) {
                $storageAccount = Create-RandomStorageAccount -storageName $storageName -rsgName $rsgName -rsgLocation $rsgLocation -VMName $vmName
                $storageName = $storageAccount.StorageAccountName
                $storageKeys = Get-AzureRmStorageAccountKey -ResourceGroupName $rsgName -Name $storageName;
                $storageKey = $storageKeys[0].Value;
            }else{
                $storageKey = "mockup key for testing, set ProductionRun=true"
            }

            if ([string]::IsNullOrEmpty($storageKey)) {
                Write-Host "#$vmName" "Failed to install the diagnostics extension due to empty storageKey for StorageAccount  " $storageName -ForegroundColor red
                return "Failed to install the diagnostics extension due to empty storageKey for StorageAccount or Account not found."
            }

            #Write-Host "#$vmName" "storageKey:" $storageKey

            $vmLocation = $rsgLocation
            $settingsString = '{
  "StorageAccount": "'+$storageName+'",
  "ladCfg": {
    "diagnosticMonitorConfiguration": {
      "eventVolume": "Medium",
      "metrics": {
        "metricAggregation": [
          {
            "scheduledTransferPeriod": "PT1H"
          },
          {
            "scheduledTransferPeriod": "PT1M"
          }
        ],
        "resourceId": "'+$vmId+'"
      },
      "performanceCounters": {
        "performanceCounterConfiguration": [
            {
                "class": "processor",
                "annotation": [
                    {
                        "displayName": "CPU IO wait time",
                        "locale": "en-us"
                    }
                ],
                "condition": "IsAggregate=TRUE",
                "counter": "percentiowaittime",
                "counterSpecifier": "/builtin/processor/percentiowaittime",
                "type": "builtin",
                "unit": "Percent",
                "sampleRate": "PT15S"
            },
            {
                "class": "processor",
                "annotation": [
                    {
                        "displayName": "CPU user time",
                        "locale": "en-us"
                    }
                ],
                "condition": "IsAggregate=TRUE",
                "counter": "percentusertime",
                "counterSpecifier": "/builtin/processor/percentusertime",
                "type": "builtin",
                "unit": "Percent",
                "sampleRate": "PT15S"
            },
            {
                "class": "processor",
                "annotation": [
                    {
                        "displayName": "CPU nice time",
                        "locale": "en-us"
                    }
                ],
                "condition": "IsAggregate=TRUE",
                "counter": "percentnicetime",
                "counterSpecifier": "/builtin/processor/percentnicetime",
                "type": "builtin",
                "unit": "Percent",
                "sampleRate": "PT15S"
            },
            {
                "class": "processor",
                "annotation": [
                    {
                        "displayName": "CPU percentage guest OS",
                        "locale": "en-us"
                    }
                ],
                "condition": "IsAggregate=TRUE",
                "counter": "percentprocessortime",
                "counterSpecifier": "/builtin/processor/percentprocessortime",
                "type": "builtin",
                "unit": "Percent",
                "sampleRate": "PT15S"
            },
            {
                "class": "processor",
                "annotation": [
                    {
                        "displayName": "CPU interrupt time",
                        "locale": "en-us"
                    }
                ],
                "condition": "IsAggregate=TRUE",
                "counter": "percentinterrupttime",
                "counterSpecifier": "/builtin/processor/percentinterrupttime",
                "type": "builtin",
                "unit": "Percent",
                "sampleRate": "PT15S"
            },
            {
                "class": "processor",
                "annotation": [
                    {
                        "displayName": "CPU idle time",
                        "locale": "en-us"
                    }
                ],
                "condition": "IsAggregate=TRUE",
                "counter": "percentidletime",
                "counterSpecifier": "/builtin/processor/percentidletime",
                "type": "builtin",
                "unit": "Percent",
                "sampleRate": "PT15S"
            },
            {
                "class": "processor",
                "annotation": [
                    {
                        "displayName": "CPU privileged time",
                        "locale": "en-us"
                    }
                ],
                "condition": "IsAggregate=TRUE",
                "counter": "percentprivilegedtime",
                "counterSpecifier": "/builtin/processor/percentprivilegedtime",
                "type": "builtin",
                "unit": "Percent",
                "sampleRate": "PT15S"
            },
            {
                "class": "memory",
                "annotation": [
                    {
                        "displayName": "Memory available",
                        "locale": "en-us"
                    }
                ],
                "counter": "availablememory",
                "counterSpecifier": "/builtin/memory/availablememory",
                "type": "builtin",
                "unit": "Bytes",
                "sampleRate": "PT15S"
            },
            {
                "class": "memory",
                "annotation": [
                    {
                        "displayName": "Swap percent used",
                        "locale": "en-us"
                    }
                ],
                "counter": "percentusedswap",
                "counterSpecifier": "/builtin/memory/percentusedswap",
                "type": "builtin",
                "unit": "Percent",
                "sampleRate": "PT15S"
            },
            {
                "class": "memory",
                "annotation": [
                    {
                        "displayName": "Memory used",
                        "locale": "en-us"
                    }
                ],
                "counter": "usedmemory",
                "counterSpecifier": "/builtin/memory/usedmemory",
                "type": "builtin",
                "unit": "Bytes",
                "sampleRate": "PT15S"
            },
            {
                "class": "memory",
                "annotation": [
                    {
                        "displayName": "Page reads",
                        "locale": "en-us"
                    }
                ],
                "counter": "pagesreadpersec",
                "counterSpecifier": "/builtin/memory/pagesreadpersec",
                "type": "builtin",
                "unit": "CountPerSecond",
                "sampleRate": "PT15S"
            },
            {
                "class": "memory",
                "annotation": [
                    {
                        "displayName": "Swap available",
                        "locale": "en-us"
                    }
                ],
                "counter": "availableswap",
                "counterSpecifier": "/builtin/memory/availableswap",
                "type": "builtin",
                "unit": "Bytes",
                "sampleRate": "PT15S"
            },
            {
                "class": "memory",
                "annotation": [
                    {
                        "displayName": "Swap percent available",
                        "locale": "en-us"
                    }
                ],
                "counter": "percentavailableswap",
                "counterSpecifier": "/builtin/memory/percentavailableswap",
                "type": "builtin",
                "unit": "Percent",
                "sampleRate": "PT15S"
            },
            {
                "class": "memory",
                "annotation": [
                    {
                        "displayName": "Mem. percent available",
                        "locale": "en-us"
                    }
                ],
                "counter": "percentavailablememory",
                "counterSpecifier": "/builtin/memory/percentavailablememory",
                "type": "builtin",
                "unit": "Percent",
                "sampleRate": "PT15S"
            },
            {
                "class": "memory",
                "annotation": [
                    {
                        "displayName": "Pages",
                        "locale": "en-us"
                    }
                ],
                "counter": "pagespersec",
                "counterSpecifier": "/builtin/memory/pagespersec",
                "type": "builtin",
                "unit": "CountPerSecond",
                "sampleRate": "PT15S"
            },
            {
                "class": "memory",
                "annotation": [
                    {
                        "displayName": "Swap used",
                        "locale": "en-us"
                    }
                ],
                "counter": "usedswap",
                "counterSpecifier": "/builtin/memory/usedswap",
                "type": "builtin",
                "unit": "Bytes",
                "sampleRate": "PT15S"
            },
            {
                "class": "memory",
                "annotation": [
                    {
                        "displayName": "Memory percentage",
                        "locale": "en-us"
                    }
                ],
                "counter": "percentusedmemory",
                "counterSpecifier": "/builtin/memory/percentusedmemory",
                "type": "builtin",
                "unit": "Percent",
                "sampleRate": "PT15S"
            },
            {
                "class": "memory",
                "annotation": [
                    {
                        "displayName": "Page writes",
                        "locale": "en-us"
                    }
                ],
                "counter": "pageswrittenpersec",
                "counterSpecifier": "/builtin/memory/pageswrittenpersec",
                "type": "builtin",
                "unit": "CountPerSecond",
                "sampleRate": "PT15S"
            },
            {
                "class": "network",
                "annotation": [
                    {
                        "displayName": "Network in guest OS",
                        "locale": "en-us"
                    }
                ],
                "counter": "bytesreceived",
                "counterSpecifier": "/builtin/network/bytesreceived",
                "type": "builtin",
                "unit": "Bytes",
                "sampleRate": "PT15S"
            },
            {
                "class": "network",
                "annotation": [
                    {
                        "displayName": "Network total bytes",
                        "locale": "en-us"
                    }
                ],
                "counter": "bytestotal",
                "counterSpecifier": "/builtin/network/bytestotal",
                "type": "builtin",
                "unit": "Bytes",
                "sampleRate": "PT15S"
            },
            {
                "class": "network",
                "annotation": [
                    {
                        "displayName": "Network out guest OS",
                        "locale": "en-us"
                    }
                ],
                "counter": "bytestransmitted",
                "counterSpecifier": "/builtin/network/bytestransmitted",
                "type": "builtin",
                "unit": "Bytes",
                "sampleRate": "PT15S"
            },
            {
                "class": "network",
                "annotation": [
                    {
                        "displayName": "Network collisions",
                        "locale": "en-us"
                    }
                ],
                "counter": "totalcollisions",
                "counterSpecifier": "/builtin/network/totalcollisions",
                "type": "builtin",
                "unit": "Count",
                "sampleRate": "PT15S"
            },
            {
                "class": "network",
                "annotation": [
                    {
                        "displayName": "Packets received errors",
                        "locale": "en-us"
                    }
                ],
                "counter": "totalrxerrors",
                "counterSpecifier": "/builtin/network/totalrxerrors",
                "type": "builtin",
                "unit": "Count",
                "sampleRate": "PT15S"
            },
            {
                "class": "network",
                "annotation": [
                    {
                        "displayName": "Packets sent",
                        "locale": "en-us"
                    }
                ],
                "counter": "packetstransmitted",
                "counterSpecifier": "/builtin/network/packetstransmitted",
                "type": "builtin",
                "unit": "Count",
                "sampleRate": "PT15S"
            },
            {
                "class": "network",
                "annotation": [
                    {
                        "displayName": "Packets received",
                        "locale": "en-us"
                    }
                ],
                "counter": "packetsreceived",
                "counterSpecifier": "/builtin/network/packetsreceived",
                "type": "builtin",
                "unit": "Count",
                "sampleRate": "PT15S"
            },
            {
                "class": "network",
                "annotation": [
                    {
                        "displayName": "Packets sent errors",
                        "locale": "en-us"
                    }
                ],
                "counter": "totaltxerrors",
                "counterSpecifier": "/builtin/network/totaltxerrors",
                "type": "builtin",
                "unit": "Count",
                "sampleRate": "PT15S"
            },
            {
                "class": "filesystem",
                "annotation": [
                    {
                        "displayName": "Filesystem transfers/sec",
                        "locale": "en-us"
                    }
                ],
                "condition": "IsAggregate=TRUE",
                "counter": "transferspersecond",
                "counterSpecifier": "/builtin/filesystem/transferspersecond",
                "type": "builtin",
                "unit": "CountPerSecond",
                "sampleRate": "PT15S"
            },
            {
                "class": "filesystem",
                "annotation": [
                    {
                        "displayName": "Filesystem % free space",
                        "locale": "en-us"
                    }
                ],
                "condition": "IsAggregate=TRUE",
                "counter": "percentfreespace",
                "counterSpecifier": "/builtin/filesystem/percentfreespace",
                "type": "builtin",
                "unit": "Percent",
                "sampleRate": "PT15S"
            },
            {
                "class": "filesystem",
                "annotation": [
                    {
                        "displayName": "Filesystem % used space",
                        "locale": "en-us"
                    }
                ],
                "condition": "IsAggregate=TRUE",
                "counter": "percentusedspace",
                "counterSpecifier": "/builtin/filesystem/percentusedspace",
                "type": "builtin",
                "unit": "Percent",
                "sampleRate": "PT15S"
            },
            {
                "class": "filesystem",
                "annotation": [
                    {
                        "displayName": "Filesystem used space",
                        "locale": "en-us"
                    }
                ],
                "condition": "IsAggregate=TRUE",
                "counter": "usedspace",
                "counterSpecifier": "/builtin/filesystem/usedspace",
                "type": "builtin",
                "unit": "Bytes",
                "sampleRate": "PT15S"
            },
            {
                "class": "filesystem",
                "annotation": [
                    {
                        "displayName": "Filesystem read bytes/sec",
                        "locale": "en-us"
                    }
                ],
                "condition": "IsAggregate=TRUE",
                "counter": "bytesreadpersecond",
                "counterSpecifier": "/builtin/filesystem/bytesreadpersecond",
                "type": "builtin",
                "unit": "CountPerSecond",
                "sampleRate": "PT15S"
            },
            {
                "class": "filesystem",
                "annotation": [
                    {
                        "displayName": "Filesystem free space",
                        "locale": "en-us"
                    }
                ],
                "condition": "IsAggregate=TRUE",
                "counter": "freespace",
                "counterSpecifier": "/builtin/filesystem/freespace",
                "type": "builtin",
                "unit": "Bytes",
                "sampleRate": "PT15S"
            },
            {
                "class": "filesystem",
                "annotation": [
                    {
                        "displayName": "Filesystem % free inodes",
                        "locale": "en-us"
                    }
                ],
                "condition": "IsAggregate=TRUE",
                "counter": "percentfreeinodes",
                "counterSpecifier": "/builtin/filesystem/percentfreeinodes",
                "type": "builtin",
                "unit": "Percent",
                "sampleRate": "PT15S"
            },
            {
                "class": "filesystem",
                "annotation": [
                    {
                        "displayName": "Filesystem bytes/sec",
                        "locale": "en-us"
                    }
                ],
                "condition": "IsAggregate=TRUE",
                "counter": "bytespersecond",
                "counterSpecifier": "/builtin/filesystem/bytespersecond",
                "type": "builtin",
                "unit": "BytesPerSecond",
                "sampleRate": "PT15S"
            },
            {
                "class": "filesystem",
                "annotation": [
                    {
                        "displayName": "Filesystem reads/sec",
                        "locale": "en-us"
                    }
                ],
                "condition": "IsAggregate=TRUE",
                "counter": "readspersecond",
                "counterSpecifier": "/builtin/filesystem/readspersecond",
                "type": "builtin",
                "unit": "CountPerSecond",
                "sampleRate": "PT15S"
            },
            {
                "class": "filesystem",
                "annotation": [
                    {
                        "displayName": "Filesystem write bytes/sec",
                        "locale": "en-us"
                    }
                ],
                "condition": "IsAggregate=TRUE",
                "counter": "byteswrittenpersecond",
                "counterSpecifier": "/builtin/filesystem/byteswrittenpersecond",
                "type": "builtin",
                "unit": "CountPerSecond",
                "sampleRate": "PT15S"
            },
            {
                "class": "filesystem",
                "annotation": [
                    {
                        "displayName": "Filesystem writes/sec",
                        "locale": "en-us"
                    }
                ],
                "condition": "IsAggregate=TRUE",
                "counter": "writespersecond",
                "counterSpecifier": "/builtin/filesystem/writespersecond",
                "type": "builtin",
                "unit": "CountPerSecond",
                "sampleRate": "PT15S"
            },
            {
                "class": "filesystem",
                "annotation": [
                    {
                        "displayName": "Filesystem % used inodes",
                        "locale": "en-us"
                    }
                ],
                "condition": "IsAggregate=TRUE",
                "counter": "percentusedinodes",
                "counterSpecifier": "/builtin/filesystem/percentusedinodes",
                "type": "builtin",
                "unit": "Percent",
                "sampleRate": "PT15S"
            },
            {
                "class": "disk",
                "annotation": [
                    {
                        "displayName": "Disk read guest OS",
                        "locale": "en-us"
                    }
                ],
                "condition": "IsAggregate=TRUE",
                "counter": "readbytespersecond",
                "counterSpecifier": "/builtin/disk/readbytespersecond",
                "type": "builtin",
                "unit": "BytesPerSecond",
                "sampleRate": "PT15S"
            },
            {
                "class": "disk",
                "annotation": [
                    {
                        "displayName": "Disk writes",
                        "locale": "en-us"
                    }
                ],
                "condition": "IsAggregate=TRUE",
                "counter": "writespersecond",
                "counterSpecifier": "/builtin/disk/writespersecond",
                "type": "builtin",
                "unit": "CountPerSecond",
                "sampleRate": "PT15S"
            },
            {
                "class": "disk",
                "annotation": [
                    {
                        "displayName": "Disk transfer time",
                        "locale": "en-us"
                    }
                ],
                "condition": "IsAggregate=TRUE",
                "counter": "averagetransfertime",
                "counterSpecifier": "/builtin/disk/averagetransfertime",
                "type": "builtin",
                "unit": "Seconds",
                "sampleRate": "PT15S"
            },
            {
                "class": "disk",
                "annotation": [
                    {
                        "displayName": "Disk transfers",
                        "locale": "en-us"
                    }
                ],
                "condition": "IsAggregate=TRUE",
                "counter": "transferspersecond",
                "counterSpecifier": "/builtin/disk/transferspersecond",
                "type": "builtin",
                "unit": "CountPerSecond",
                "sampleRate": "PT15S"
            },
            {
                "class": "disk",
                "annotation": [
                    {
                        "displayName": "Disk write guest OS",
                        "locale": "en-us"
                    }
                ],
                "condition": "IsAggregate=TRUE",
                "counter": "writebytespersecond",
                "counterSpecifier": "/builtin/disk/writebytespersecond",
                "type": "builtin",
                "unit": "BytesPerSecond",
                "sampleRate": "PT15S"
            },
            {
                "class": "disk",
                "annotation": [
                    {
                        "displayName": "Disk read time",
                        "locale": "en-us"
                    }
                ],
                "condition": "IsAggregate=TRUE",
                "counter": "averagereadtime",
                "counterSpecifier": "/builtin/disk/averagereadtime",
                "type": "builtin",
                "unit": "Seconds",
                "sampleRate": "PT15S"
            },
            {
                "class": "disk",
                "annotation": [
                    {
                        "displayName": "Disk write time",
                        "locale": "en-us"
                    }
                ],
                "condition": "IsAggregate=TRUE",
                "counter": "averagewritetime",
                "counterSpecifier": "/builtin/disk/averagewritetime",
                "type": "builtin",
                "unit": "Seconds",
                "sampleRate": "PT15S"
            },
            {
                "class": "disk",
                "annotation": [
                    {
                        "displayName": "Disk total bytes",
                        "locale": "en-us"
                    }
                ],
                "condition": "IsAggregate=TRUE",
                "counter": "bytespersecond",
                "counterSpecifier": "/builtin/disk/bytespersecond",
                "type": "builtin",
                "unit": "BytesPerSecond",
                "sampleRate": "PT15S"
            },
            {
                "class": "disk",
                "annotation": [
                    {
                        "displayName": "Disk reads",
                        "locale": "en-us"
                    }
                ],
                "condition": "IsAggregate=TRUE",
                "counter": "readspersecond",
                "counterSpecifier": "/builtin/disk/readspersecond",
                "type": "builtin",
                "unit": "CountPerSecond",
                "sampleRate": "PT15S"
            },
            {
                "class": "disk",
                "annotation": [
                    {
                        "displayName": "Disk queue length",
                        "locale": "en-us"
                    }
                ],
                "condition": "IsAggregate=TRUE",
                "counter": "averagediskqueuelength",
                "counterSpecifier": "/builtin/disk/averagediskqueuelength",
                "type": "builtin",
                "unit": "Count",
                "sampleRate": "PT15S"
            }
        ]
    },
    "syslogEvents": {
        "syslogEventConfiguration": {
            "LOG_AUTH": "LOG_ERR",
            "LOG_AUTHPRIV": "LOG_ERR",
            "LOG_CRON": "LOG_ERR",
            "LOG_DAEMON": "LOG_ERR",
            "LOG_FTP": "LOG_ERR",
            "LOG_KERN": "LOG_ERR",
            "LOG_LOCAL0": "LOG_ERR",
            "LOG_LOCAL1": "LOG_ERR",
            "LOG_LOCAL2": "LOG_ERR",
            "LOG_LOCAL3": "LOG_ERR",
            "LOG_LOCAL4": "LOG_ERR",
            "LOG_LOCAL5": "LOG_ERR",
            "LOG_LOCAL6": "LOG_ERR",
            "LOG_LOCAL7": "LOG_ERR",
            "LOG_LPR": "LOG_ERR",
            "LOG_MAIL": "LOG_ERR",
            "LOG_NEWS": "LOG_ERR",
            "LOG_SYSLOG": "LOG_ERR",
            "LOG_USER": "LOG_ERR",
            "LOG_UUCP": "LOG_ERR"
        }
    }
    },
    "sampleRateInSeconds": 15
  }
}
'

            $settingsStringPath = Join-Path $deployExtensionLogDir "linuxsettings.json"

            Out-File -FilePath $settingsStringPath -Force -Encoding utf8 -InputObject $settingsString

            $extensionPublisher = 'Microsoft.Azure.Diagnostics'
            $extensionVersion = "3.0"
            $protectedSettings  = '{
    "storageAccountName": "'+$storageName+'",
    "storageAccountKey": "'+$storageKey+'"
}'
            $extensionType = "LinuxDiagnostic"

            Write-Host "#$vmName" "Set-AzureRmVMExtension $rsgName -VMName $vmName -Name $extensionName -AsJob" -ForegroundColor Yellow
            if ($ProductionRun -eq $true) {
                $result = Set-AzureRmVMExtension -ResourceGroupName $rsgName -VMName $vmName -Name $extensionName -Publisher $extensionPublisher -ExtensionType $extensionType -TypeHandlerVersion $extensionVersion -Settingstring $settingsString -ProtectedSettingString $protectedSettings -Location $vmLocation -AsJob
                return $result.StatusCode
            }

            return "Mockup Done"

        }


        function Enable-WindowsDiagnosticsExtension($vm, $rsg, $rsgName, $rsgLocation,$vmId,$vmName,$storageName){
            $extensionName = "Microsoft.Insights.VMDiagnosticsSettings"
            $extensionType = "IaaSDiagnostics"
            Write-Host "#$vmName Get-AzureRmVMDiagnosticsExtension -ResourceGroupName $rsgName -VMName $vmName | Where-Object -Property ExtensionType -eq $extensionType"
            $extension = Get-AzureRmVMDiagnosticsExtension -ResourceGroupName $rsgName -VMName $vmName | Where-Object -Property ExtensionType -eq $extensionType
            Write-Host "#$vmName" " Extension state " $extension.ProvisioningState
            if($extension -and $extension.ProvisioningState -eq 'Succeeded'){
                if ($cleanup -eq $true) {
                    Write-Host "#$vmName" "Remove-AzureRmVMExtension $rsgName -VMName $vmName -Name " $extension.Name " -Force"
                    if ($ProductionRun -eq $true)
                    {
                        $Response = Remove-AzureRmVMExtension -ResourceGroupName $rsgName -VMName $vmName -Name $extension.Name  -Force
                        return "Remove Extension Done - Windows." + $Response.StatusCode
                    }else{
                        return "Mockup remove."
                    }

                }else{
                    Write-Host "#$vmName" "just skip,due to diagnostics extension had been installed in VM before,you can update the diagnostics settings via portal or powershell cmdlets by yourself"
                    return  "Skip due to diagnostics extension had been installed "
                }
            }elseif ($cleanup -eq $true) {
                Write-Host "#$vmName" "Not need to clean up Extension for $rsgName -VMName $vmName -Name $extensionName"
                return "No Extension need cleanup"
            }

            Write-Host "#$vmName" "start to install the diagnostics extension for windows VM"

            $storageKey = ""
            Write-Host "#$vmName" "use storageName:" $storageName
            if ($ProductionRun -eq $true) {
                $storageAccount = Create-RandomStorageAccount -storageName $storageName -rsgName $rsgName -rsgLocation $rsgLocation  -VMName $vmName
                $storageKeys = Get-AzureRmStorageAccountKey -ResourceGroupName $rsgName -Name $storageName;
                $storageKey = $storageKeys[0].Value;
            }else{
                $storageKey = "mockup key for ProductionRun=false"
            }

            if ([string]::IsNullOrEmpty($storageKey)) {
                Write-Host "#$vmName" "Failed to install the diagnostics extension due to empty storageKey for StorageAccount  " $storageName -ForegroundColor red
                return "Failed to install the diagnostics extension due to empty storageKey for StorageAccount or StorageAccount not found. " +$storageName
            }

            #Write-Host "#$vmName" "storageKey:" $storageKey

            $vmLocation = $rsgLocation

            $extensionTemplate = '{
    "$schema": "http://schema.management.azure.com/schemas/2015-01-01/deploymentTemplate.json#",
    "contentVersion": "1.0.0.0",
    "parameters": {},
    "variables": {},
    "resources": [
        {
            "type": "Microsoft.Compute/virtualMachines/extensions",
            "name": "'+$vmName+'/'+$extensionName+'",
            "apiVersion": "2016-04-30-preview",
            "location": "'+$vmLocation+'",
            "properties": {
                "publisher": "Microsoft.Azure.Diagnostics",
                "type": "IaaSDiagnostics",
                "typeHandlerVersion": "1.5",
                "autoUpgradeMinorVersion": true,
                "protectedSettings": {
                    "storageAccountName": "'+$storageName+'",
                    "storageAccountKey": "'+$storageKey+'",
                    "storageAccountEndPoint": "https://core.windows.net"
                },
                "settings": {
                    "StorageAccount": "'+$storageName+'",
                    "WadCfg": {
                        "DiagnosticMonitorConfiguration": {
                            "overallQuotaInMB": 5120,
                            "Metrics": {
                                "resourceId": "'+$vmId+'",
                                "MetricAggregation": [
                                    {
                                        "scheduledTransferPeriod": "PT1H"
                                    },
                                    {
                                        "scheduledTransferPeriod": "PT1M"
                                    }
                                ]
                            },
                            "DiagnosticInfrastructureLogs": {
                                "scheduledTransferLogLevelFilter": "Error",
                                "scheduledTransferPeriod": "PT1M"
                            },
                            "PerformanceCounters": {
                                "scheduledTransferPeriod": "PT1M",
                                "PerformanceCounterConfiguration": [
                                    {
                                        "counterSpecifier": "\\Processor Information(_Total)\\% Processor Time",
                                        "unit": "Percent",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\Processor Information(_Total)\\% Privileged Time",
                                        "unit": "Percent",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\Processor Information(_Total)\\% User Time",
                                        "unit": "Percent",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\Processor Information(_Total)\\Processor Frequency",
                                        "unit": "Count",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\System\\Processes",
                                        "unit": "Count",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\Process(_Total)\\Thread Count",
                                        "unit": "Count",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\Process(_Total)\\Handle Count",
                                        "unit": "Count",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\System\\System Up Time",
                                        "unit": "Count",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\System\\Context Switches/sec",
                                        "unit": "CountPerSecond",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\System\\Processor Queue Length",
                                        "unit": "Count",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\Memory\\% Committed Bytes In Use",
                                        "unit": "Percent",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\Memory\\Available Bytes",
                                        "unit": "Bytes",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\Memory\\Committed Bytes",
                                        "unit": "Bytes",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\Memory\\Cache Bytes",
                                        "unit": "Bytes",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\Memory\\Pool Paged Bytes",
                                        "unit": "Bytes",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\Memory\\Pool Nonpaged Bytes",
                                        "unit": "Bytes",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\Memory\\Pages/sec",
                                        "unit": "CountPerSecond",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\Memory\\Page Faults/sec",
                                        "unit": "CountPerSecond",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\Process(_Total)\\Working Set",
                                        "unit": "Count",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\Process(_Total)\\Working Set - Private",
                                        "unit": "Count",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\LogicalDisk(_Total)\\% Disk Time",
                                        "unit": "Percent",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\LogicalDisk(_Total)\\% Disk Read Time",
                                        "unit": "Percent",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\LogicalDisk(_Total)\\% Disk Write Time",
                                        "unit": "Percent",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\LogicalDisk(_Total)\\% Idle Time",
                                        "unit": "Percent",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\LogicalDisk(_Total)\\Disk Bytes/sec",
                                        "unit": "BytesPerSecond",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\LogicalDisk(_Total)\\Disk Read Bytes/sec",
                                        "unit": "BytesPerSecond",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\LogicalDisk(_Total)\\Disk Write Bytes/sec",
                                        "unit": "BytesPerSecond",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\LogicalDisk(_Total)\\Disk Transfers/sec",
                                        "unit": "BytesPerSecond",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\LogicalDisk(_Total)\\Disk Reads/sec",
                                        "unit": "BytesPerSecond",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\LogicalDisk(_Total)\\Disk Writes/sec",
                                        "unit": "BytesPerSecond",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\LogicalDisk(_Total)\\Avg. Disk sec/Transfer",
                                        "unit": "Count",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\LogicalDisk(_Total)\\Avg. Disk sec/Read",
                                        "unit": "Count",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\LogicalDisk(_Total)\\Avg. Disk sec/Write",
                                        "unit": "Count",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\LogicalDisk(_Total)\\Avg. Disk Queue Length",
                                        "unit": "Count",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\LogicalDisk(_Total)\\Avg. Disk Read Queue Length",
                                        "unit": "Count",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\LogicalDisk(_Total)\\Avg. Disk Write Queue Length",
                                        "unit": "Count",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\LogicalDisk(_Total)\\% Free Space",
                                        "unit": "Percent",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\LogicalDisk(_Total)\\Free Megabytes",
                                        "unit": "Count",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\Network Interface(*)\\Bytes Total/sec",
                                        "unit": "BytesPerSecond",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\Network Interface(*)\\Bytes Sent/sec",
                                        "unit": "BytesPerSecond",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\Network Interface(*)\\Bytes Received/sec",
                                        "unit": "BytesPerSecond",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\Network Interface(*)\\Packets/sec",
                                        "unit": "BytesPerSecond",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\Network Interface(*)\\Packets Sent/sec",
                                        "unit": "BytesPerSecond",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\Network Interface(*)\\Packets Received/sec",
                                        "unit": "BytesPerSecond",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\Network Interface(*)\\Packets Outbound Errors",
                                        "unit": "Count",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\Network Interface(*)\\Packets Received Errors",
                                        "unit": "Count",
                                        "sampleRate": "PT60S"
                                    }
                                ]
                            },
                            "WindowsEventLog": {
                                "scheduledTransferPeriod": "PT1M",
                                "DataSource": [
                                    {
                                        "name": "Application!*[Application[(Level=1 or Level=2 or Level=3)]]"
                                    },
                                    {
                                        "name": "System!*[System[(Level=1 or Level=2 or Level=3)]]"
                                    },
                                    {
                                        "name": "Security!*[System[(band(Keywords,4503599627370496))]]"
                                    }
                                ]
                            },
                            "Directories": {
                                "scheduledTransferPeriod": "PT1M"
                            }
                        }
                    }
                }
            }
        }
    ]
}'
            $fileName = "windowsvm_extension_$rsgName_$vmName.json"
            $extensionTemplatePath = Join-Path $deployExtensionLogDir $fileName;
            #Out-File -FilePath $extensionTemplatePath -Force -Encoding utf8 -InputObject $extensionTemplate
            Set-Content -Path $extensionTemplatePath -Value $extensionTemplate -Encoding utf8
            Write-Host "#$vmName New-AzureRmResourceGroupDeployment  $rsgName  $extensionTemplatePath -AsJob " -ForegroundColor Yellow
            if ($ProductionRun -eq $true) {
                $result = New-AzureRmResourceGroupDeployment -ResourceGroupName $rsgName -TemplateFile $extensionTemplatePath -AsJob
                return "Done - Status Code = " + $result.StatusCode
            }

            Remove-Item  -Path  $extensionTemplatePath -Force
            return "Mockup Done."
        }

        function Enable-VMDiagnosticsExtension($vm)
        {

            $vmName = $vm.Name
            Write-Host "#$vmName - Process Enable-VMDiagnosticsExtension"

            $status=$vm | Get-AzureRmVM -Status
            if ($status.Statuses[1].DisplayStatus -ne "VM running")
            {
                Write-Host "#"$vm.Name " is not running. Skip."
                return "Skip due to VM Not running."
            }
            $rsgName = $vm.ResourceGroupName;
            $rsg = Get-AzureRmResourceGroup -Name $rsgName
            $rsgLocation = $vm.Location;

            $vmId = $vm.Id

            Write-Host "#$vmName - vmId:" $vmId

            $osType = $vm.StorageProfile.OsDisk.OsType
            Write-Host "#$vmName" "  OsType:" $osType

            # Start to check the RSG name
            $storageName = ""
            $storageKey = ""
            if($diagnosticStorageAccountName){
                $storageName = $diagnosticStorageAccountName
            }else{
                $storageName  =Get-RandomStorageName -id $rsg.ResourceId
            }

            $result = "VM " + $vmName + " , result: "
            if($osType -eq 0){
                Write-Host "#$vmName" "  This vm type is windows"
                $result += Enable-WindowsDiagnosticsExtension -vm $vm -rsg $rsg -rsgName $rsgName -rsgLocation $rsgLocation -vmId $vmId -vmName $vmName -storageName $storageName
            } else {
                Write-Host "#$vmName" "  This vm type is linux"
                $result += Enable-LinuxDiagnosticsExtension  -vm $vm -rsg $rsg  -rsgName $rsgName -rsgLocation $rsgLocation -vmId $vmId -vmName $vmName -storageName $storageName
            }
            return $result

        }
        Write-Host ""


        $id = $vm.Name

        Write-Host "#$id - " "diagnosticStorageAccountName = " $diagnosticStorageAccountName
        Write-Host "#$id - " "storageType = " $storageType
        Write-Host "#$id - " "storageNamePrefix = " $storageNamePrefix
        Write-Host "#$id - " "deployExtensionLogDir = " $deployExtensionLogDir
        Write-Host "#$id - " "ProductionRun = " $ProductionRun
        Write-Host "#$id - " "cleanup = " $cleanup
        Write-Host ""

        Write-Host "#$id Starting processing"

        $result = Enable-VMDiagnosticsExtension $vm

        #Test-FUN

        $DateTime =  Date
        $logStr = "#$id - " + $DateTime + " " + " Job Finished -- " + $result
        Write-Host  $logStr  -ForegroundColor Yellow
        Write-Host ""

    }

    $threads = @()

    $handles = for ($i = 0; $i -lt $vmList.Count; $i++) {
        $vm = $vmList[$i]
        Write-Host  "Create Job" $vm.Name  -ForegroundColor red
        # $powershell = [powershell]::Create().AddScript($ScriptBlock).AddArgument($vm)

        $powershell = [powershell]::Create().AddScript($ScriptBlock).AddArgument($vm).AddArgument($diagnosticStorageAccountName).AddArgument($storageType).AddArgument($storageNamePrefix).AddArgument($deployExtensionLogDir).AddArgument($ProductionRun).AddArgument($cleanup)

        $powershell.RunspacePool = $Pool
        $powershell.BeginInvoke()
        $threads += $powershell
    }

    $logfile = ".\log.txt"
    $totalCount = $handles.Count
    do {
        $i = 0
        $done = $true
        $doneCount =0
        $doingCount =0
        foreach ($handle in $handles) {
            if ($handle -ne $null) {
                if ($handle.IsCompleted) {
                    $threads[$i].EndInvoke($handle)
                    $threads[$i].Dispose()
                    if ($totalCount -gt 1)
                    {
                        $handles[$i] = $null
                    }
                } else {
                    $done = $false
                    $doingCount++
                }
            }

            $i++
        }

        $doneCount = $totalCount - $doingCount
        $logStr = "Total Job Count = $totalCount . job finished  $doneCount , job doing  $doingCount "
        Write-Host  $logStr  -ForegroundColor Yellow
        # Add-Content  -Path $logfile  -Value  $logStr

        if (-not $done) {
            Start-Sleep -Milliseconds 5000
        }

    } until ($done)

    $Pool.Dispose()
    [System.GC]::Collect()

}

function Process-Subscription($Subscription){
    $SubscriptionId = $Subscription.SubscriptionId
    $SubscriptionName =$Subscription.Name;
    Get-AzureRmSubscription –SubscriptionName  $SubscriptionName | Select-AzureRmSubscription
    Write-Host "Process Subscription"  $SubscriptionName $SubscriptionId -ErrorAction Stop　
    #  if($subscriptionId){
    #      Login-AzureRmAccount -SubscriptionId $subscriptionId -ErrorAction Stop
    #  } else {
    #      Login-AzureRmAccount -ErrorAction Stop
    #  }
    Write-Host "Starting process for SubscriptionId " (Get-AzureRmContext).Subscription -ForegroundColor Yellow
    $vmList = $null
    if($targetVmName -and $targetRsgName){
        Write-Host "you have input the rsg name:" $targetRsgName " vm's name:" $targetVmName
        $vmList = Get-AzureRmVM -Name $targetVmName -ResourceGroupName $targetRsgName
    } elseif ($targetRsgName){
        Write-Host "you have input the target rsg name " $targetRsgName " and will retrieve vms under this group."
        $vmList = Get-AzureRmVM -ResourceGroupName $targetRsgName
    } else {
        Write-Host "Retrieve all vms"
        $vmList = Get-AzureRmVM
    }

    if($vmList){
        Write-Host "vms count: " $vmList.Count
        Write-Host ""
        # if($ThreadCount -le 1){
        #     $i = 0
        #     foreach($vm in $vmList){
        #         $i++
        #         $resultStr = Enable-VMDiagnosticsExtension -index $i -vm $vm
        #         Write-Host $resultStr -ForegroundColor Yellow
        #         Write-Host ""
        #     }
        # }

        Enable-Diagnostics-multi-thread -vmList $vmList  -diagnosticStorageAccountName $diagnosticStorageAccountName  -storageType $storageType -storageNamePrefix $storageNamePrefix -deployExtensionLogDir $deployExtensionLogDir -ProductionRun $ProductionRun -cleanup $cleanup

    } else {
        Write-Host "no vms exist"
    }
}


Write-Host "This script is using for Foglight Azure Agent Enable VM diagnostic in your all subscriptions"
Write-Host ""
Write-Host "Getting the subscriptions List from Azure, please wait..." -ForegroundColor Yellow
$Subscriptions = Get-AzureRmSubscription

if($Subscriptions -eq $null){
    Write-Host "Login-AzureRmAccount"
    Login-AzureRmAccount -ErrorAction Stop
}

Write-Host "All Subscriptions:" -ForegroundColor Yellow
foreach ($entry in $Subscriptions) { Write-Host " " + $entry.Name -ForegroundColor Yellow }

Write-Host "------------------------------------------------------"

Write-Host ""
$SubscriptionsSize = $Subscriptions.Count
if ($SubscriptionName){
    Write-Host "Selected Subscriptions by SubscriptionName:" $SubscriptionName
    $Subscriptions = $Subscriptions | where { $_.SubscriptionName -EQ $SubscriptionName }
}
elseif ($SubscriptionId){
    Write-Host "Selected Subscriptions by SubscriptionId:" $SubscriptionId
    $Subscriptions = $Subscriptions | where { $_.SubscriptionId -EQ $SubscriptionId }
}

if($SubscriptionsSize -ne $Subscriptions.Count){
    Write-Host "Subscriptions selected:" -ForegroundColor Yellow
    foreach ($entry in $Subscriptions) { Write-Host " " + $entry.Name -ForegroundColor Yellow }

    Write-Host "------------------------------------------------------"
}

Write-Host ""
foreach ( $Subscription in $Subscriptions ) {
    Process-Subscription $Subscription
    Write-Host ""
    Write-Host ""
}
Write-Host "Done!"
if ($ProductionRun -ne $true) {
    Write-Host "Nothing Changes. Please set ProductionRun to $true to make changes. " -ForegroundColor Cyan
}
