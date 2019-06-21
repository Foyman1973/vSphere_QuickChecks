<#        
    .SYNOPSIS
     A brief summary of the commands in the file.

    .DESCRIPTION
    A detailed description of the commands in the file.

    .NOTES
    ========================================================================
         Windows PowerShell Source File 
         Created with SAPIEN Technologies PrimalScript 2017
         
         NAME: vSphere_Checks.ps1
         
         AUTHOR: Jason Foy , DaVita Inc.
         DATE  : 10/31/2017
         
         COMMENT: Master vSphere System Checks Script
         
    ==========================================================================
#>
Clear-Host
$Tests = @('Dead LUN Path','Offline VM Test','Offline Host Test','Ping All VM on Cluster','Ping All VM on Host','Host Serial Numbers','QUIT')
$Version = "1.0.4"
$ScriptName = $MyInvocation.MyCommand.Name
$scriptPath = Split-Path $MyInvocation.MyCommand.Path
$StartTime = Get-Date
$Date = Get-Date -Format g
$dateSerial = Get-Date -Format yyyyMMddHHmmss
Write-Host ("="*80) -ForegroundColor DarkGreen
Write-Host ""
Write-Host `t`t"$scriptName v$Version"
Write-Host `t`t"Started $Date"
Write-Host ""
Write-Host ("="*80) -ForegroundColor DarkGreen
Write-Host ""
# $vCenterList = Import-Csv "C:\Transfer\Dropbox\Scripts\Powershell\VMware\CONTROL\vCenterList_SBX.csv" -Delimiter ","
$vCenterList = Import-Csv "D:\SCRIPTS\CONTROL\vCenterList.csv" -Delimiter ","
$filePath = Join-Path -Path $scriptPath -ChildPath "Reports"
Write-Host "Report Path:" $filePath
$DeadPathFileName = Join-Path -Path $filePath -ChildPath "DeadPathReport_$dateSerial.csv"
$OfflineVMFilePathName = Join-Path -Path $filePath -ChildPath "OfflineVMReport_$dateSerial.csv"
$OfflineHostFilePathName = Join-Path -Path $filePath -ChildPath "OfflineHostReport_$dateSerial.csv"
$HostSerialNumFilePathName = Join-Path -Path $filePath -ChildPath "HostSerialNumReport_$dateSerial.csv"
if(!(Test-Path $filePath)){New-Item -ItemType Directory -Path $filePath|Out-Null}
# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
function Check-PowerCLIv3{
	$pCLIpresent=$false
	Get-Module -Name VMware* -ListAvailable | Import-Module -ErrorAction SilentlyContinue
	Add-PSSnapin VMware.VimAutomation.Core -ErrorAction SilentlyContinue
	try{$myVersion = Get-PowerCLIVersion;$pCLIpresent=$true}
	catch{}
	return $pCLIpresent
}
# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
function Write-Menu{
	Clear-Host
	Write-Host "========================================================" -ForegroundColor Yellow
	Write-Host ""
	Write-Host "        Welcome to the vSphere Quick Checks" -ForegroundColor Yellow
	Write-Host ""
	Write-Host "       Please select from the choices below." -ForegroundColor Yellow
	Write-Host ""
	Write-Host "vCenters:$goodvCenters of $($vCenterList.Count)"
	Write-Host "========================================================" -ForegroundColor Yellow
	Write-Host ""
    Write-Host ("-"*30) -ForegroundColor DarkGreen    
    $choice = @{}
    for($i=1;$i -le $Tests.count;$i++){
        Write-Host "  $i ...... $($Tests[$i-1])"
        $choice.Add($i,$($Tests[$i-1]))
    }
    Write-Host ("-"*30) -ForegroundColor DarkGreen
    Write-Host "   Select Test (1-$($Tests.count))" -NoNewline -ForegroundColor Yellow
    [int]$answer = Read-Host ":"
    $myTest = $choice.Item($answer)
#     Write-Host "You Selected: " -NoNewline;Write-Host $myTest -ForegroundColor Cyan	
	Write-Host ("="*50) -ForegroundColor DarkGreen
	return $myTest
}
# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
function Check-DeadPaths{
	Write-Host "";Write-Host "Available Datacenter Values" -ForegroundColor Yellow
	Write-Host ("-"*50) -foregroundcolor Yellow
	$myDatacenters = Get-Datacenter|sort Name
	$myDatacenters|select Name -Unique|ft -AutoSize
	Write-Host ("-"*50) -foregroundcolor Yellow
	Write-Host ""
	Write-Host "Provide 1 or more Datacenters (comma list)"
	$datacenterList = Read-Host	"Accepts * wildcards (i.e. sea*  sea*,den3  or just * for any)"
	Write-Host ""
	Write-Host ("-"*50) -foregroundcolor Yellow	
	Write-Host "Gathering Host List..." -ForegroundColor White -NoNewline
	$hostList = Get-Datacenter $datacenterList|Get-VMHost|?{$_.ConnectionState -match "Connected|Maintenance"}|sort Name
	$hostCount = $hostList.Count
	Write-Host $hostCount;Write-Host ""
	$x=1
	$deadPathList = @()
	foreach($vmHost in $hostList){
		$TotalPaths = 0;$deadPaths = 0
		$vmHostName = $vmHost.Name
		Write-Progress -Id 1 -Activity "Checking Host Paths..." -CurrentOperation $vmHostName -PercentComplete (($x/$hostCount)*100);$x++
		$TotalPaths = ($vmHost.ExtensionData.Config.StorageDevice.MultipathInfo.Lun.Path).Count
		$dpCount = 0
		if ((($vmHost.ExtensionData.Config.StorageDevice.MultipathInfo.Lun.Path|?{$_.State -eq "Dead"}).Count) -gt 0){
			$vmHost.ExtensionData.Config.StorageDevice.MultipathInfo.Lun|%{$_.Path}|?{$_.State -eq "Dead"}|%{
				$myPath = ""|select Name,State,HBA,Path
				$myPath.Name = $vmHostName
				$myPath.State = $_.State
				$myPath.HBA = $_.Adapter
				$myPath.Path = $_.Name
				$deadPathList += $myPath
				$dpCount++
			}
		}
		if ($dpCount -gt 0){
			Write-Host $vmHost -ForegroundColor Cyan -NoNewline
			Write-Host " $dpCount paths down" -ForegroundColor Red -BackgroundColor Black -NoNewline
			$pctDown = [math]::round((($dpCount/$TotalPaths)*100),0)
			Write-Host " [ $pctDown % ]" -ForegroundColor Yellow
		}
	}
	Write-Progress -Id 1 -Completed -Activity "Checking Host Paths..."
	if ($deadPathList.Count -gt 0){
		$deadPathList|Export-Csv $DeadPathFileName -Force
		Write-Host ""
		Write-Host "Dead Path Summary:" -ForegroundColor Yellow
		Write-Host "***   Send File to ISG VMware and Team USB ***" -ForegroundColor Yellow -BackgroundColor Black
		Write-Host "[ $DeadPathFileName ]" -ForegroundColor Cyan
		Write-Host ("*"*50) -foregroundcolor Yellow
		Write-Host ""
		$uniqueHosts = $deadPathList|select Name -Unique
		$uniquePaths = ($deadPathList|select Path -Unique).Count
		Write-Host "Impacted Hosts:" -ForegroundColor White -NoNewline;Write-Host ($uniqueHosts.Name).Count -ForegroundColor Cyan
		Write-Host "Impacted Paths:" -ForegroundColor White -NoNewline;Write-Host $uniquePaths -ForegroundColor Cyan
		Write-Host
		Write-Host ("*"*50) -foregroundcolor Yellow
	}
	else{
		Write-Host ("-"*50) -foregroundcolor DarkGreen
		Write-Host "";Write-Host "No Dead Paths Found" -ForegroundColor Green -BackgroundColor Black;Write-Host ""
		Write-Host ("-"*50) -foregroundcolor DarkGreen
	}
	Wait-Here
}
# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
function Check-OfflineVM{
	Write-Host ""
	Write-Host "Checking for Offline Virtual Servers...." -ForegroundColor Green
	Write-Host ("-"*50) -ForegroundColor DarkGreen
	$OfflineVMreport = @()
	$OfflineVM = Get-View -ViewType VirtualMachine -Filter @{'Runtime.ConnectionState'='disconnected|inaccessible|invalid|orphaned'}
	Write-Host "Offline VM Count:" -NoNewline
	if($OfflineVM.Count -gt 0){
		Write-Host $offlineVM.Count -ForegroundColor Red
		Write-Host "writing Details..."
		$OfflineVM|%{
			$row=""|select Name,State,VMHost,VMHostState
			$row.Name = $_.Name
			$row.State = $_.Runtime.ConnectionState
			$thisVMHost = Get-VMHost -id ("$(($_.Runtime.Host).Type)"+"-"+"$(($_.Runtime.Host).Value)")
			$row.VMHost = $thisVMHost.Name
			$row.VMHostState = "$($thisVMHost.State),$($thisVMHost.ConnectionState),$($thisVMHost.PowerState)"
			$OfflineVMreport += $row
			Write-Host	"VM:" -ForegroundColor Cyan -NoNewline
			Write-Host $_.Name -NoNewline
			Write-Host `t`t"VMHost:" -ForegroundColor Cyan -NoNewline
			Write-Host " $($thisVMHost.Name) [ $($thisVMHost.ConnectionState) ]"
		}
		$OfflineVMreport|Export-Csv -NoTypeInformation $OfflineVMFilePathName -Force
		Write-Host "";Write-Host ("*"*50) -ForegroundColor Yellow
		Write-Host "***   Send File to ISG VMware ***" -ForegroundColor Yellow -BackgroundColor Black
		Write-Host "[ $OfflineVMFilePathName ]" -ForegroundColor Cyan
		Write-Host ("*"*50) -ForegroundColor Yellow
	}
	else{Write-Host $offlineVM.Count -ForegroundColor Green}
	Write-Host ("-"*50) -ForegroundColor DarkGreen
	Wait-Here
}
# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
function Check-OfflineHost {
	Write-Host ""
	Write-Host "Checking for Offline ESXi Servers...." -ForegroundColor Green
	Write-Host ("-"*50) -ForegroundColor DarkGreen
	$OfflineHostReport = @()
	$OfflineHost = Get-View -ViewType HostSystem -Filter @{'Runtime.ConnectionState'='Disconnected|NotResponding'}
	Write-Host "Offline ESXi Count:" -NoNewline
	if($OfflineHost.Count -gt 0){
		Write-Host $OfflineHost.Count -ForegroundColor Red
		Write-Host "writing Details..."
		$OfflineHost|%{
			$row=""|select Name,State,PowerState
			$row.Name = $_.Name
			$row.State = $_.Runtime.ConnectionState
			$row.PowerState = $_.Runtime.PowerState
			$OfflineHostReport += $row
			Write-Host	"Host:" -ForegroundColor Cyan -NoNewline
			Write-Host $_.Name -NoNewline
			Write-Host " [ $($_.Runtime.ConnectionState) ]" -ForegroundColor Yellow
		}
		$OfflineHostReport|Export-Csv -NoTypeInformation $OfflineHostFilePathName -Force
		Write-Host "";Write-Host ("*"*50) -ForegroundColor Yellow
		Write-Host "***   Send File to ISG VMware ***" -ForegroundColor Yellow -BackgroundColor Black
		Write-Host "[ $OfflineHostFilePathName ]" -ForegroundColor Cyan
		Write-Host ("*"*50) -ForegroundColor Yellow
	}
	else{Write-Host $OfflineHost.Count -ForegroundColor Green}
	Write-Host ("-"*50) -ForegroundColor DarkGreen
	Wait-Here
}
# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
function Wait-Here{
	Write-Host "";Write-Host "Press any key to continue ..."
	$wait4it = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
function Ping-HostVM{
	Write-Host ""
	Write-Host "Ping VMs on Single Host" -ForegroundColor Green
	Write-Host ("-"*50) -ForegroundColor DarkGreen
	Write-Host "";$myResponse = Read-Host "Enter full ESXi host name as displayed in vCenter:"
	$thisVMhost = Get-VMHost $myResponse -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
	if($thisVMhost){
		Write-Host "Getting VMs on $($thisVMhost.Name)"
		$thisVMset = $thisVMhost|Get-VM|select Name,PowerState| sort Name
		Write-Host "Pinging Guests on $($thisVMhost.Name)...[ $($thisVMset.Count) ]"
		foreach ($vm in $thisVMset) {
		    $guest = $vm.Name
		    $PowerState = $vm.PowerState
		    $ping = New-Object System.Net.NetworkInformation.Ping
		    try{$status = [string]($ping.Send($guest)).Status}
		    catch [System.Net.NetworkInformation.PingException]{$status = $null}
		    switch($status){
		        'Success' {
		        	if ($PowerState -eq "PoweredOff"){
		        		Write-Host `t"GOOD`t" -ForegroundColor Green -BackgroundColor Black -NoNewline;Write-Host "$guest`t" -NoNewline;Write-Host "$PowerState" -ForegroundColor red -BackgroundColor yellow
		        	}
		        	Else {
		        		Write-Host `t"GOOD`t" -ForegroundColor Green -BackgroundColor Black -NoNewline;Write-Host "$guest`t" -NoNewline;Write-Host "$PowerState"
		        	}
		        }
		        Default {
		        	if ($PowerState -eq "PoweredOff"){
		        		Write-Host `t"FAIL`t" -ForegroundColor red -BackgroundColor yellow -NoNewline;Write-Host "$guest`t" -NoNewline; Write-Host "$PowerState" -ForegroundColor red -BackgroundColor yellow
		        	}
		        	Else {
		        		Write-Host `t"FAIL`t" -ForegroundColor red -BackgroundColor yellow -NoNewline;Write-Host "$guest`t" -NoNewline; Write-Host "$PowerState"
		        	}
		        }
		    }
		}
	}
	else{Write-Host "Invalid Host" -ForegroundColor Red}
	Write-Host ("-"*50) -ForegroundColor DarkGreen
	Wait-Here
}
# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
function Ping-ClusterVM{
	Write-Host ""
	Write-Host "Ping All VM in a Cluster" -ForegroundColor Green
	Write-Host ("-"*50) -ForegroundColor DarkGreen
	Write-Host "";$myResponse = Read-Host "Enter Cluster name as displayed in vCenter:"
	$thisCluster = Get-Cluster $myResponse -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
	if($thisCluster){
		Write-Host "Getting VMs on $($thisCluster.Name)"
		$thisVMset = $thisCluster|Get-VM|select Name,PowerState,VMHost| sort Name
		Write-Host "Pinging Guests on $($thisCluster.Name)...[ $($thisVMset.Count) ]"
		foreach ($vm in $thisVMset) {
		    $guest = $vm.Name
		    $PowerState = $vm.PowerState
		    $thisVMHost = $vm.VMHost
		    $ping = New-Object System.Net.NetworkInformation.Ping
		    try{$status = [string]($ping.Send($guest)).Status}
		    catch [System.Net.NetworkInformation.PingException]{$status = $null}
		    switch($status){
		        'Success' {
		        	if ($PowerState -eq "PoweredOff"){
		        		Write-Host `t"GOOD`t" -ForegroundColor Green -BackgroundColor Black -NoNewline;Write-Host "$guest [$thisVMHost] `t" -NoNewline; Write-Host "$PowerState" -ForegroundColor red -BackgroundColor yellow
		        	}
		        	Else {
		        		Write-Host `t"GOOD`t" -ForegroundColor Green -BackgroundColor Black -NoNewline;Write-Host "$guest [$thisVMHost] `t" -NoNewline; Write-Host "$PowerState"
		        	}
		        }
		        Default {
		        	if ($PowerState -eq "PoweredOff"){
		        		Write-Host `t"FAIL`t" -ForegroundColor red -BackgroundColor yellow -NoNewline; Write-Host "$guest [$thisVMHost] `t" -NoNewline; Write-Host "$PowerState" -ForegroundColor red -BackgroundColor yellow
		        	}
		        	Else {
		        		Write-Host `t"FAIL`t" -ForegroundColor red -BackgroundColor yellow -NoNewline; Write-Host "$guest [$thisVMHost] `t" -NoNewline; Write-Host "$PowerState"
		        	}
		        }
		    }
		}
	}
	else{Write-Host "Invalid Cluster" -ForegroundColor Red}
	Write-Host ("-"*50) -ForegroundColor DarkGreen
	Wait-Here
}
# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
function Check-HostSerialNumbers{
	Write-Host ""
	Write-Host "ESXi Host Serial Number Report" -ForegroundColor Green
	Write-Host ("-"*50) -ForegroundColor DarkGreen
	Write-Host "Getting Hosts..." -NoNewline
	$myVMHosts = Get-View -ViewType HostSystem
	Write-Host "[ $($myVMHosts.Count) ]"
	$vmHostSerialReport = @()
	Write-Host "Getting Serial Numbers..."
	$myVMHosts|%{
		$row = ""|select Name, Vendor, Model, ProductID, SerialNumber
		$thisServerModel = $_.Hardware.SystemInfo.Model
		$row.Model = $thisServerModel
		$thisField0 = $_.Hardware.SystemInfo.OtherIdentifyingInfo.IdentifierValue[0]
		$thisField1 = $_.Hardware.SystemInfo.OtherIdentifyingInfo.IdentifierValue[1]
		$thisField2 = $_.Hardware.SystemInfo.OtherIdentifyingInfo.IdentifierValue[2]
		$thisField3 = $_.Hardware.SystemInfo.OtherIdentifyingInfo.IdentifierValue[3]
		$thisField4 = $_.Hardware.SystemInfo.OtherIdentifyingInfo.IdentifierValue[4]
		switch -wildcard ($thisServerModel){
			'UCSC-C240-M3S'{
				$thisProductID = "NA"
				$thisServerSerial = $thisField2
			}
			'NX*'{
				$thisProductID = "NA"
				$thisServerSerial = $thisField0
			}
			'ProLiant DL580 G7'{
				$thisProductID = $thisField2.Replace("Product ID: ","")
				$thisServerSerial = $thisField3
			}
			'ProLiant DL580 Gen9'{
				$thisProductID = $thisField2.Replace("Product ID: ","")
				$thisServerSerial = $thisField4
			}
			'ProLiant DL380 G7'{
				$thisProductID = $thisField2.Replace("Product ID: ","")
				$thisServerSerial = $thisField3
			}
			'ProLiant DL380p Gen8'{
				$thisProductID = $thisField2.Replace("Product ID: ","")
				$thisServerSerial = $thisField3
			}
			'ProLiant DL380 Gen9'{
				$thisProductID = $thisField2.Replace("Product ID: ","")
				$thisServerSerial = $thisField4
			}
			'ProLiant BL460c Gen9'{
				$thisProductID = $thisField1.Replace("Product ID: ","")
				$thisServerSerial = $thisField0
			}
			'ProLiant XL170r Gen9'{
				$thisProductID = $thisField1.Replace("Product ID: ","")
				$thisServerSerial = $thisField4
			}
			"System x3650 M5*" {
				$splitString = $($thisServerModel.Split(":"))[1]
				$splitString = $($splitString.replace(' -[','')).replace(']-','')
				$thisServerSerial = $splitString
				$thisProductID = "NA"
				$row.Model = $($thisServerModel.Split(":"))[0]
			}
			Default{
				$thisProductID = "Needs Configuration"
				$thisServerSerial = "Needs Configuration"
			}
		}
		$row.Name = $_.Name
		$row.Vendor = $_.Hardware.SystemInfo.Vendor
		$row.ProductID = $thisProductID
		$row.SerialNumber = $thisServerSerial
		$vmHostSerialReport += $row
	}
	Write-Host "Exporting Data..."
	$vmHostSerialReport|Export-Csv -NoTypeInformation $HostSerialNumFilePathName -Force
	Write-Host ""
	Write-Host "***   ESXi Host Serial Number Report ***" -ForegroundColor Yellow -BackgroundColor Black
	Write-Host "[ $HostSerialNumFilePathName ]" -ForegroundColor Cyan
	Write-Host ""
	Write-Host ("-"*50) -ForegroundColor DarkGreen
	Wait-Here
}
# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
Write-Host "Checking PowerCLI Snap-in..." -NoNewline
if(!(Check-PowerCLIv3)){Write-Host "No PowerCLI Installed" -ForegroundColor Red;exit}
Else{Write-Host "GOOD" -ForegroundColor Green}
$stopwatch = [Diagnostics.Stopwatch]::StartNew()
$loggedIN = $false
$myLoginCreds = Get-Credential -Message "Enter vCenter Username and Password"
$goodvCenters = 0
Write-Host "Connecting to vCenter Instances..." -ForegroundColor Cyan
$vCenterList|%{
	$vConn=""
	$vConn = Connect-VIServer $_.Name -Credential $myLoginCreds -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
	if($vConn){Write-Host $_.Name -ForegroundColor Green;$loggedIN=$true;$goodvCenters++}
	else{Write-Host	$_.Name -ForegroundColor Red -NoNewline;Write-Host	" Login Failed!" -ForegroundColor Yellow}
}
$TestSelection = ""
if($loggedIN){
	do{
		$TestSelection = Write-Menu
		switch($TestSelection){
			'Dead LUN Path' {Check-DeadPaths}
			'Offline VM Test' {Check-OfflineVM}
			'Offline Host Test' {Check-OfflineHost}
			'Ping All VM on Cluster'{Ping-ClusterVM}
			'Ping All VM on Host' {Ping-HostVM}
			'Host Serial Numbers' {Check-HostSerialNumbers}
			'QUIT' {Write-Host "Quit Selected, Exiting Script..." -ForegroundColor Yellow;Disconnect-VIServer * -Confirm:$false}
		}
	}
	until($TestSelection -eq "QUIT")
}
else{Write-Host "vCenter Connection failed" -ForegroundColor Red}
$stopwatch.Stop()
$Elapsed = [math]::Round(($stopwatch.elapsedmilliseconds)/1000,1)
Write-Host "Script Complete [ $Elapsed seconds ]"
