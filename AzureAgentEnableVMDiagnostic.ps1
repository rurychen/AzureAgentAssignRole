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

    $cleanup

)

$subscriptionId = "XXXXXX"
$targetRsgName = "RuryTest"
#$targetVmName = "rurytestlinux"
$diagnosticStorageAccountName = "vmdiagnostic20190906"
$storageType = "Standard_LRS"
$storageNamePrefix = "autonamevmdiagnostic20190906"
$deployExtensionLogDir = split-path -parent $MyInvocation.MyCommand.Definition
$ProductionRun = $false

if ([string]::IsNullOrEmpty($cleanup)) {
    $cleanup = $False;
}
Write-Host "Clean up is " $cleanup

function Create-RandomStorageAccount($rsgName,$rsgLocation,$storageName){
    Write-Host "Get-AzureRmStorageAccount -ResourceGroupName" $rsgName  "-AccountName" $storageName
    $storageAccount = Get-AzureRmStorageAccount -ResourceGroupName $rsgName -AccountName $storageName
    if($storageAccount){
        Write-Host "Use the exist StorageAccount " $storageName
        return $storageAccount
    }else{
        Write-Host "New-AzureRmStorageAccount -ResourceGroupName $rsgName -AccountName $storageName -Location $rsgLocation -Type $storageType"
        $storageAccount = New-AzureRmStorageAccount -ResourceGroupName $rsgName -AccountName $storageName -Location $rsgLocation -Type $storageType
        return $storageAccount
    }
}

function Get-RandomStorageName(){
    $randomResult = ""
    for($i = 0;$i -lt 10;$i++){
        $random = Get-Random -Maximum 9 -Minimum 0
        $randomResult+=$random
    }
    $storageName = $storageNamePrefix+$randomResult
    return $storageName
}
# if the extension has existed, just skip
function Enable-LinuxDiagnosticsExtension($vm,$rsg,$rsgName,$rsgLocation,$vmId,$vmName){
    $extensionType="LinuxDiagnostic"
    $extensionName = "LinuxDiagnostic"

    Write-Host "Get-AzureRmVM -Name $vmName -ResourceGroupName $rsgName"
    $vm = Get-AzureRmVM -Name $vmName -ResourceGroupName $rsgName
    $extension = $vm.Extensions | Where-Object -Property 'VirtualMachineExtensionType' -eq $extensionType
    Write-Host " Extension " $vmName " state " $vm $extension.ProvisioningState
    if( $extension -and $extension.ProvisioningState -eq 'Succeeded'){
        if ($cleanup -eq $true) {
            Write-Host "Remove-AzureRmVMExtension $rsgName -VMName $vmName -Name $extensionName -Force"
            if ($ProductionRun -eq $true)
            {
                Remove-AzureRmVMExtension -ResourceGroupName $rsgName -VMName $vmName -Name $extensionName -Force
                return "Remove Extension"
            }
            return "Mockup Remove"
        }else{
            Write-Host " just skip,due to diagnostics extension had been installed in VM: "$vmName " before,you can update the diagnostics settings via portal or powershell cmdlets by yourself."
            return "Skip due to diagnostics extension had been installed"
        }

    }elseif ($cleanup -eq $true) {
        Write-Host "Not need to clean up Extension for $rsgName -VMName $vmName -Name $extensionName"
        return "No Extension need cleanup"
    }

    Write-Host "start to install the diagnostics extension for linux VM" $vmName

    $storageName = ""
    $storageKey = ""
    if($diagnosticStorageAccountName){
        $storageName = $diagnosticStorageAccountName
    }else{
        $storageName  =Get-RandomStorageName
    }
    Write-Host "storageName:" $storageName

    if ($ProductionRun -eq $true) {
        $storageAccount = Create-RandomStorageAccount -storageName $storageName -rsgName $rsgName -rsgLocation $rsgLocation
        $storageName = $storageAccount.StorageAccountName
        $storageKeys = Get-AzureRmStorageAccountKey -ResourceGroupName $rsgName -Name $storageName;
        $storageKey = $storageKeys[0].Value;
    }else{
        $storageKey = "mockup key for testing, set ProductionRun=true"
    }

    if ([string]::IsNullOrEmpty($storageKey)) {
        Write-Host "Failed to install the diagnostics extension due to empty storageKey for StorageAccount  " $storageName -ForegroundColor red
        return "Failed"
    }

    #Write-Host "storageKey:" $storageKey

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

    Write-Host "Set-AzureRmVMExtension $rsgName -VMName $vmName -Name $extensionName"
    if ($ProductionRun -eq $true) {
        $result = Set-AzureRmVMExtension -ResourceGroupName $rsgName -VMName $vmName -Name $extensionName -Publisher $extensionPublisher -ExtensionType $extensionType -TypeHandlerVersion $extensionVersion -Settingstring $settingsString -ProtectedSettingString $protectedSettings -Location $vmLocation
        return $result.StatusCode
    }

    return "Mockup Done"

}


function Enable-WindowsDiagnosticsExtension($vm, $rsg, $rsgName, $rsgLocation,$vmId,$vmName){
    $extensionName = "IaaSDiagnostics"
    $extensionType = "IaaSDiagnostics"

    $extension = Get-AzureRmVMDiagnosticsExtension -ResourceGroupName $rsgName -VMName $vmName | Where-Object -Property ExtensionType -eq $extensionType
    if($extension -and $extension.ProvisioningState -eq 'Succeeded'){
        if ($cleanup -eq $true) {
            Write-Host "Remove-AzureRmVMExtension $rsgName -VMName $vmName -Name $extensionName -Force"
            if ($ProductionRun -eq $true)
            {
                Remove-AzureRmVMExtension -ResourceGroupName $rsgName -VMName $vmName -Name $extensionName  -Force
            }
            return "Mockup remove."
        }else{
            Write-Host "just skip,due to diagnostics extension had been installed in VM: "$vmName " before,you can update the diagnostics settings via portal or powershell cmdlets by yourself"
            return  "Skip due to diagnostics extension had been installed "
        }
    }elseif ($cleanup -eq $true) {
        Write-Host "Not need to clean up Extension for $rsgName -VMName $vmName -Name $extensionName"
        return "Skip due to Not need to clean up Extension"
    }

    Write-Host "start to install the diagnostics extension for windows VM"

    $storageName = ""
    $storageKey = ""
    if($diagnosticStorageAccountName){
        $storageName = $diagnosticStorageAccountName
    }else{
        $storageName  = Get-RandomStorageName
    }
    Write-Host "storageName:" $storageName
    if ($ProductionRun -eq $true) {
        $storageAccount = Create-RandomStorageAccount -storageName $storageName -rsgName $rsgName -rsgLocation $rsgLocation
        $storageKeys = Get-AzureRmStorageAccountKey -ResourceGroupName $rsgName -Name $storageName;
        $storageKey = $storageKeys[0].Value;
    }else{
        $storageKey = "mockup key for ProductionRun=false"
    }

    if ([string]::IsNullOrEmpty($storageKey)) {
        Write-Host "Failed to install the diagnostics extension due to empty storageKey for StorageAccount  " $storageName -ForegroundColor red
        return "Failed to install the diagnostics extension due to empty storageKey for StorageAccount " +$storageName
    }

    #Write-Host "storageKey:" $storageKey

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
    $extensionTemplatePath = Join-Path $deployExtensionLogDir "extensionTemplateForWindows.json";
    Out-File -FilePath $extensionTemplatePath -Force -Encoding utf8 -InputObject $extensionTemplate
    Write-Host "New-AzureRmResourceGroupDeployment " $rsgName  $extensionTemplatePath

    if ($ProductionRun -eq $true) {
        $result = New-AzureRmResourceGroupDeployment -ResourceGroupName $rsgName -TemplateFile $extensionTemplatePath
        return $result.StatusCode
    }
    return "Mockup Done."
}


function Enable-VMDiagnosticsExtension($index, $vm)
{

    Write-Host "Process " $vm.Name " job index: " $index

    $status=$vm | Get-AzureRmVM -Status
    if ($status.Statuses[1].DisplayStatus -ne "VM running")
    {
        Write-Host $vm.Name" is not running. Skip."
        return "Skip due to VM Not running."
    }
    $rsgName = $vm.ResourceGroupName;
    $rsg = Get-AzureRmResourceGroup -Name $rsgName
    $rsgLocation = $vm.Location;

    $vmId = $vm.Id
    $vmName = $vm.Name
    Write-Host "  vmId:" $vmId
    Write-Host "  vmName:" $vmName

    $osType = $vm.StorageProfile.OsDisk.OsType
    Write-Host "  OsType:" $osType

    $result = "VM " + $vmName + " , result: "
    if($osType -eq 0){
        Write-Host "  This vm type is windows"
        $result += Enable-WindowsDiagnosticsExtension -vm $vm -rsg $rsg -rsgName $rsgName -rsgLocation $rsgLocation -vmId $vmId -vmName $vmName
    } else {
        Write-Host "  This vm type is linux"
        $result += Enable-LinuxDiagnosticsExtension  -vm $vm -rsg $rsg  -rsgName $rsgName -rsgLocation $rsgLocation -vmId $vmId -vmName $vmName
    }
    return $result

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
        $i = 0
        foreach($vm in $vmList){
            $i++
            $resultStr = Enable-VMDiagnosticsExtension -index $i -vm $vm
            Write-Host $resultStr -ForegroundColor Yellow
            Write-Host ""
        }
    } else {
        Write-Host "no vms exist"
    }
}


Write-Host "This script is using for Foglight Azure Agent Enable VM diagnostic in your all subscriptions"
Write-Host ""
Write-Host "Getting the subscriptions List from Azure, please wait..." -ForegroundColor Yellow
$Subscriptions = Get-AzureRmSubscription
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
