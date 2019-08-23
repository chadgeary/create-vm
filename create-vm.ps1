#!/usr/bin/pwsh
# https://github.com/chadgeary
# Get VM options then create vm from template
# Fancy line
function Fancyline {
 for($i=0; $i -lt (Get-Host).ui.rawui.buffersize.width; $i++) {Write-Host -nonewline -ForegroundColor Magenta -BackgroundColor White "@"}
}

# DNS must resolve to IP
while (!$dnscheck) {
        $vmname = Read-Host "VM name? DNS must resolve."
        $dnscheck = [System.Net.Dns]::GetHostEntry($vmname)
}

# Set VM IP from DNS
Fancyline
$vmip = $dnscheck.AddressList.IPAddressToString
Write-Host "DNS OK: VM IP set to $vmip"

# Set gateway from IP, only works 100% for /24 networks
$vmgw = $vmip.Split(".")
$vmgw[-1] = 1
$vmgw = $vmgw -join "."
Write-Host "VM gateway set to $vmgw"

# Choose an environment folder
Fancyline
while ($pick_environmentname -lt 1) {[int]$pick_environmentname = Read-Host "which folder (environment)?
1. linux_prod
2. linux_dev
3. linux_uat
"}
        Switch ($pick_environmentname)
        {
                1 {$environmentname = "linux_prod"}
                2 {$environmentname = "linux_dev"}
                3 {$environmentname = "linux_uat"}
	}

# Choose a network name
Fancyline
while ($pick_vmnetwork -lt 1) {[int]$pick_vmnetwork = Read-Host "which network?
1. 192.168.10_PROD
2. 192.168.11_DEV
3. 192.168.12_UAT
"}
	Switch ($pick_vmnetwork)
	{
		1 {$vmnetwork = "192.168.10_PROD"}
		2 {$vmnetwork = "192.168.11_DEV"}
		3 {$vmnetwork = "192.168.12_UAT"}
	}
# Pick cores
Fancyline
while ($vmcpu -lt 1) {[int]$vmcpu = Read-Host "Number of cores?"}

# Pick memgb
Fancyline
while ($vmmemgb -lt 1) {[int]$vmmemgb = Read-Host "How much memory (GBs)?"}

# Pick template
Fancyline
while ($pick_vmtemplate -lt 1) {[int]$pick_vmtemplate = Read-Host "Which template?
1. rhel6standard
2. rhel7standard
3. rhel7minimal
4. rhel8minimal
5. ubuntu1804minimal
"}
	Switch ($pick_vmtemplate)
	{
                1 {$vmtemplate = "rhel6standard"}
		2 {$vmtemplate = "rhel7standard"}
		3 {$vmtemplate = "rhel7minimal"}
                4 {$vmtemplate = "rhel8minimal"}
                5 {$vmtemplate = "ubuntu1804minimal"}
	}

# Choose vcenter
Fancyline
while ($pick_vcenterhost -lt 1) {[int]$pick_vcenterhost = Read-Host "which vcenter?
10. vcenter1.chadg.net # VCENTER1
20. vcenter2.chadg.net
"}
	Switch ($pick_vcenterhost)
	{
                10 {$vcenterhost = "vcenter1.chadg.net"}
		20 {$vcenterhost = "vcenter2.chadg.net"}
	}

# Pick cluster
Fancyline
while ($pick_vmcluster -lt 1) {[int]$pick_vmcluster = Read-Host "which cluster?
10. LINUX-CLUSTER-1
20. LINUX-CLUSTER-2
"}
	Switch ($pick_vmcluster)
	{
                10 {$vmcluster = "LINUX-CLUSTER-1"}
		20 {$vmcluster = "LINUX-CLUSTER-2"}
	}

# Pick storage
Fancyline
while ($pick_storage -lt 1) {[int]$pick_storage = Read-Host "Which storage?
10. LINUX-MAGNETIC # Linux Standard NFS
20. LINUX-SOLIDSTATE # Linux Fast NFS
"}
        Switch ($pick_storage)
        {
                10 {$vmstorage = "linux-magnetic*"}
		11 {$vmstorage = "linux-solidstate*"}
        }

# Summary
Fancyline
Write-Host "Variables set:"
Write-Host "vm: $vmname"
Write-Host "ip: $vmip"
Write-Host "gw: $vmgw"
Write-Host "folder: $environmentname"
Write-Host "net: $vmnetwork"
Write-Host "template: $vmtemplate"
Write-Host "cpu: $vmcpu"
Write-Host "memgb: $vmmemgb"
Write-Host "template: $vmtemplate"
Write-Host "vcenter: $vcenterhost"
Write-Host "cluster: $vmcluster"
Write-Host "storage: $vmstorage"

# Log
Add-Content /var/log/create-vm.log $(Get-Date -UFormat %Y-%m-%d_%H:%M:%S) -NoNewLine
Add-Content /var/log/create-vm.log (",$vmname,$vmtemplate,$vmcpu,$vmmemgb,$vmip,$vmgw,$vmnetwork,$vcenterhost,$vmcluster,$vmstorage") -NoNewline
Add-Content /var/log/create-vm.log ''

# notify slack
$scriptuser=[Environment]::UserName
$scriptmachine=[Environment]::MachineName

curl --silent -o /dev/null --header "Content-Type: application/json" --request POST --data "{ 'text': '$scriptuser creating $vmname as $vmtemplate cores: $vmcpu memgb: $vmmemgb', 'username': '$scriptmachine' }" {{ salt['pillar.get']('slackhookurl') }}

# Connect
Write-Host "Connecting to $vcenterhost. This is the point of no return (all further steps are automated)!"
while (!$defaultVIServer) {Connect-VIServer -Server $vcenterhost -Protocol https}

# Determine if VM exists already
$vmexists = Get-VM -Name $vmname -ErrorAction SilentlyContinue
if ($vmexists) {
	Write-Host "vm name check: exists; exiting!"
	Exit
} else {
	Write-Host "vm name check: ok"
	Start-Sleep 1
	Write-Host "building template from user input"
	Start-Sleep 1
}

# Create temporary VM customization specs
$vmcustomspec = New-OSCustomizationSpec -Name "linux-temporary-template" -Type NonPersistent -Domain chadg.net -OSType Linux -DnsServer "9.9.9.9","1.0.0.1" -DnsSuffix "chadg.net"

# Update Spec with IP information
$vmcustomspec | Get-OSCustomizationNicMapping | Set-OSCustomizationNicMapping -IpMode UseStaticIP -IPAddress $vmip -SubnetMask "255.255.255.0" -DefaultGateway $vmgw

# Refresh customize variable
$vmcustomspec = Get-OSCustomizationSpec -Name "linux-temporary-template"

# Set vmhost based on most free memory in cluster and storage
$vmhostname = Get-VMHost -Location $vmcluster -Datastore $vmstorage -State Connected | Select Name, @{N='MemoryFreeGB';E={[math]::Round(($_.MemoryTotalGB - $_.MemoryUsageGB),2)}} | Sort-Object -Property 'MemoryFreeGB' | Select -Last 1
$vmhost = Get-VMHost -Name $vmhostname.name
Write-Host "vm host:"$vmhost | Select Name

# Set datastore based on 1. $vmstorage name filter 2. most free gb attached to vmhost
$vmdatastore = Get-Datastore -Name $vmstorage -VMHost $vmhost | Sort-Object -Property FreeSpaceGB -Descending | Select -First 1
Write-Host "vm datastore:"$vmdatastore | Select Name

# Create VM
$vm = New-VM -Name $vmname -Template $vmtemplate -VMHost $vmhost -Datastore $vmdatastore -DiskStorageFormat Thin | Set-VM -NumCpu $vmcpu -MemoryGB $vmmemgb -OSCustomizationSpec $vmcustomspec -confirm:$false

# Power on VM
Start-VM -VM $vmname | Out-Null

# Get NIC of created VM
$nic = Get-NetworkAdapter -VM $vmname

# Refresh vmhost
$vmhost = Get-VMHost -VM $vmname

# Distributed Switch Method
$vmnicnetwork = Get-VDPortgroup -Name $vmnetwork

# Set NIC network
Set-NetworkAdapter -NetworkAdapter $nic -Portgroup $vmnicnetwork -confirm:$false | Out-Null

# Set StartConnected and Connected
Set-NetworkAdapter -NetworkAdapter $nic -StartConnected:$true -Connected:$true -confirm:$false | Out-Null

# Move to folder
$environmentfolder = Get-Folder -Name $environmentname
Move-VM -VM $vm -InventoryLocation $environmentfolder -Destination $vm.VMHost | Out-Null

# RHEL8 uuid interface and hostname post-build
if ($vmtemplate -match "rhel8.*") { 
	Write-Host "rhel8; generating uuid and running /usr/local/bin/template-helper, it may take over 1 minute."

        # generate vm uuid
        $uuiddate = Get-Date -format "dd hh mm ss"
        $uuidnew = "52 a1 3f 77 05 3c 33 62-b4 77 22 77 " + $uuiddate
        $uuidspec = New-Object VMware.Vim.VirtualMachineConfigSpec
        $uuidspec.uuid = $uuidnew

        # apply generated vm uuid
        $uuidvm = Get-VM $vmname
        $uuidvm.Extensiondata.ReconfigVM_Task($uuidspec)

	# restart the vm to (possibly) clear any customizations)
	Start-Sleep 20
        Restart-VMGuest -VM $vmname -Confirm:$false | Out-Null
	Start-Sleep 50

	# lx-templateuser
	$vmusername = "lx-templatehelper"
	$vmpassword = ConvertTo-SecureString "{{ salt['pillar.get']('lxtemplatehelperpw') }}" -AsPlainText -Force
	$vmcredential = New-Object -typename System.Management.Automation.PSCredential -ArgumentList $vmusername, $vmpassword

	# commands to set hostname gw and ip from vars
	# the script
	$rhel8script = @"
echo $vmgw > /home/lx-templatehelper/gw
cat /home/lx-templatehelper/gw
echo $vmip > /home/lx-templatehelper/ip
cat /home/lx-templatehelper/ip
echo $vmname > /home/lx-templatehelper/hostname
cat /home/lx-templatehelper/hostname
sudo /bin/systemctl enable template-helper.service
systemctl status template-helper.service
echo 'template-helper service enabled, PowerCLI must now reboot VM'
"@

	# executing the script
	Invoke-VMScript -VM $vmname -ScriptText $rhel8script -GuestCredential $vmcredential -ScriptType Bash

        # restart vm
        Restart-VMGuest -VM $vmname -Confirm:$false | Out-Null
}

Write-Host "End of vm creation, for configuration please run:"
Write-Host "ansible-genesis $vmname <test|dev|uat|production>"
