# Variables
$KeyVault = "Paaswords-for-homework"
$MachineNames = @("homework-win-00","homework-win-01","homework-win-02","homework-win-03","homework-win-04")
$DataCollectorSet = "Perf_log_EV"
$FilePath = "C:\Temp\PerfLog"
$Token = Read-Host "Please enter token for Slack message:"

# Posting message to Slack
$postSlackMessage = @{token="$token";channel="#homework";text="Script is started";username="postbot"}
Invoke-RestMethod -Uri https://slack.com/api/chat.postMessage -Body $postSlackMessage

# Check if File Path exists on local machine and creates if it doesn't
$PathExists = Test-Path $FilePath
If ($PathExists -match "False") {
    New-Item -ItemType Directory $FilePath 
    Write-Host "File Path wasn't found and it was created" -ForegroundColor Green
    } else {
        Write-Host "File Path on local machine exists" -ForegroundColor Green
    }

# Removes all blg files from path
Remove-Item "$FilePath\*.blg" 

# Check if Azure account is logged in or not and if not it will asks for credentials to log in
$LoginCheck = Get-AzContext
If ($null -eq $LoginCheck) {
    Write-Host "No Logged accounts found" -ForegroundColor Red
    $AppID = Read-Host "Please enter App ID:"
    $TenantID = Read-Host "Please enter Tenant ID:"
    $Credential = Get-Credential -Message "Please Enter Password:" -username $AppID
    $Subscription = Connect-AzAccount -Credential $Credential -Tenant $TenantID -ServicePrincipal
    $Subscription = Get-AzContext
    Write-Host "Account"$Subscription.Account"has been successfully logged in" -ForegroundColor Green
} else {
    $Subscription = Get-AzContext
    Write-Host "Account"$Subscription.Account"is logged in." -ForegroundColor Green
}

# Get list of Secret Values of Machine IPs
Write-Host "Acquiring IP addresses for VM machines" -ForegroundColor Yellow
$MachineNameIPs = foreach ($MachineName in $MachineNames) {
    (Get-AzKeyVaultSecret -VaultName $KeyVault -Name $MachineName).SecretValueText
}

# Get VM credentials
Write-Host "Acquiring VM credentials" -ForegroundColor Yellow
$VMUser = (Get-AzKeyVaultSecret -VaultName $KeyVault -Name VMUser).SecretValueText
$VMPassword = (Get-AzKeyVaultSecret -VaultName $KeyVault -Name VMPassword).SecretValueText
$SecurePassword = ConvertTo-SecureString "$VMPassword" -AsPlainText -Force
$Credential = New-Object System.Management.Automation.PSCredential("$VMUser",$SecurePassword)

# Creates PowerShell sessions for all VM's
$SessionOption = New-PSSessionOption -SkipCACheck -SkipCNCheck
ForEach ($MachineNameIP in $MachineNameIPs) {
    Write-Host "$MachineNameIP" 
    New-PSSession -ComputerName $MachineNameIP -UseSSL -SessionOption $SessionOption -Credential $Credential
}

# Takes sessions as variable
$Sessions = Get-PSSession

# Checking for each session if perf counter exists or not and creating/recreating perf counters
ForEach ($Session in $Sessions){
    $QueryCheck = Invoke-Command -Session $Session -ScriptBlock {Param($DataCollectorSet)logman query $DataCollectorSet} -ArgumentList $DataCollectorSet
    $SessionName = $Session.Name
    If ($QueryCheck -match "$DataCollectorSet") {
        Write-Host "["$Session.ComputerName"] $DataCollectorSet - Data Collector Set is already exists" -ForegroundColor Green
        $Status = Invoke-Command -Session $Session -ScriptBlock {param($DataCollectorSet);logman query $DataCollectorSet} -ArgumentList $DataCollectorSet | Select-String -Pattern 'Status'
        If ($Status -match 'Stopped') {
            Write-Host "["$Session.ComputerName"] $DataCollectorSet $Status" -ForegroundColor Green
            Write-Host "["$Session.ComputerName"] Deleting and recreating - $DataCollectorSet " -ForegroundColor Yellow
            Invoke-Command -Session $Session -ScriptBlock {Param($DataCollectorSet);logman delete $DataCollectorSet} -ArgumentList $DataCollectorSet
            Write-Host "["$Session.ComputerName"] Creating new $DataCollectorSet" -ForegroundColor Yellow
            Invoke-Command -Session $Session -ScriptBlock {Param($DataCollectorSet, $FilePath, $SessionName);logman create counter $DataCollectorSet -o "$FilePath\$SessionName.blg" -c "\Processor(_Total)\% Processor time","\Memory\Available MBytes","\PhysicalDisk(0 C:)\Disk Read Bytes/sec","\PhysicalDisk(0 C:)\Disk Write Bytes/sec","\Network Adapter(Hyper-V Virtual Ethernet Adapter)\Bytes Sent/sec","\Network Adapter(Hyper-V Virtual Ethernet Adapter)\Bytes Received/sec" -rf 01:00:00 -si 00:00:01 -max 1024 -f bincirc --v -ow} -ArgumentList $DataCollectorSet, $FilePath, $SessionName
            Write-Host "["$Session.ComputerName"] $DataCollectorSet - Data Collector Set has been created" -ForegroundColor Green
            Write-Host "["$Session.ComputerName"] Starting Data Collector Set - $DataCollectorSet" -ForegroundColor Yellow
            Invoke-Command -Session $Session -ScriptBlock {Param($DataCollectorSet);logman start $DataCollectorSet} -ArgumentList $DataCollectorSet
            Write-Host "["$Session.ComputerName"] $DataCollectorSet started" -ForegroundColor Green
        } else { 
            Write-Host "["$Session.ComputerName"] $DataCollectorSet $Status" -ForegroundColor Red
            Write-Host "["$Session.ComputerName"] $DataCollectorSet is going to be stopped/deleted and recreated" -ForegroundColor Yellow
            Write-Host "["$Session.ComputerName"] $DataCollectorSet is stopping" -ForegroundColor Yellow
            Invoke-Command -Session $Session -ScriptBlock {Param($DataCollectorSet);logman stop $DataCollectorSet} -ArgumentList $DataCollectorSet
            Write-Host "["$Session.ComputerName"] $DataCollectorSet is going to be deleted"-ForegroundColor Yellow
            Invoke-Command -Session $Session -ScriptBlock {Param($DataCollectorSet);logman delete $DataCollectorSet} -ArgumentList $DataCollectorSet
            Write-Host "["$Session.ComputerName"] Creating new $DataCollectorSet" -ForegroundColor Yellow
            Invoke-Command -Session $Session -ScriptBlock {Param($DataCollectorSet, $FilePath, $SessionName);logman create counter $DataCollectorSet -o "$FilePath\$SessionName.blg" -c "\Processor(_Total)\% Processor time","\Memory\Available MBytes","\PhysicalDisk(0 C:)\Disk Read Bytes/sec","\PhysicalDisk(0 C:)\Disk Write Bytes/sec","\Network Adapter(Hyper-V Virtual Ethernet Adapter)\Bytes Sent/sec","\Network Adapter(Hyper-V Virtual Ethernet Adapter)\Bytes Received/sec" -rf 01:00:00 -si 00:00:01 -max 1024 -f bincirc --v -ow} -ArgumentList $DataCollectorSet, $FilePath, $SessionName
            Write-Host "["$Session.ComputerName"] $DataCollectorSet - Data Collector Set has been created" -ForegroundColor Green
            Write-Host "["$Session.ComputerName"] Starting Data Collector Set - $DataCollectorSet" -ForegroundColor Yellow
            Invoke-Command -Session $Session -ScriptBlock {Param($DataCollectorSet);logman start $DataCollectorSet} -ArgumentList $DataCollectorSet
            Write-Host "["$Session.ComputerName"] $DataCollectorSet started" -ForegroundColor Green 
        }
    } else {
        Write-Host "["$Session.ComputerName"] $DataCollectorSet - Data Collector Set was not found, creating new one..." -ForegroundColor Yellow
        Invoke-Command -Session $Session -ScriptBlock {Param($DataCollectorSet, $FilePath, $SessionName);logman create counter $DataCollectorSet -o "$FilePath\$SessionName.blg" -c "\Processor(_Total)\% Processor time","\Memory\Available MBytes","\PhysicalDisk(0 C:)\Disk Read Bytes/sec","\PhysicalDisk(0 C:)\Disk Write Bytes/sec","\Network Adapter(Hyper-V Virtual Ethernet Adapter)\Bytes Sent/sec","\Network Adapter(Hyper-V Virtual Ethernet Adapter)\Bytes Received/sec" -rf 01:00:00 -si 00:00:01 -max 1024 -f bincirc --v -ow} -ArgumentList $DataCollectorSet, $FilePath, $SessionName
        Write-Host "["$Session.ComputerName"] $DataCollectorSet - Data Collector Set has been created" -ForegroundColor Green
        Write-Host "["$Session.ComputerName"] Starting Data Collector Set - $DataCollectorSet" -ForegroundColor Yellow
        Invoke-Command -Session $Session -ScriptBlock {Param($DataCollectorSet);logman start $DataCollectorSet} -ArgumentList $DataCollectorSet
        Write-Host "["$Session.ComputerName"] $DataCollectorSet started" -ForegroundColor Green
    }
}

# Checking if counters are still running
ForEach ($Session in $Sessions){
    $Status = Invoke-Command -Session $Session -ScriptBlock {param($DataCollectorSet);logman query $DataCollectorSet} -ArgumentList $DataCollectorSet | Select-String -Pattern 'Status'
                Do { 
                    Write-Host "Waiting for job to finish on"$Session.ComputerName"..." -ForegroundColor Yellow
                    $Status = Invoke-Command -Session $Session -ScriptBlock {param($DataCollectorSet);logman query $DataCollectorSet} -ArgumentList $DataCollectorSet | Select-String -Pattern 'Status'
                    Start-Sleep 20
                } While ($Status -match 'Running')
                Write-Host "Job is Finished for "$Session.ComputerName"" -ForegroundColor Green
}

# Compressing BLG file, copies to local computer and extract it (removes zipped file from remote session and local computer)
ForEach ($Session in $Sessions){
    $SessionName = $Session.Name
    Invoke-Command -Session $Session {Param($FilePath, $SessionName);Compress-Archive -Path "$FilePath\$SessionName.blg" -DestinationPath "$FilePath\$SessionName.zip" -CompressionLevel Fastest -Update} -ArgumentList $FilePath, $SessionName
    Copy-Item -LiteralPath "$FilePath\$SessionName.zip" -Destination "$FilePath\$SessionName.zip" -FromSession $Session 
    Invoke-Command -Session $Session {Param($FilePath, $SessionName);Remove-Item "$FilePath\$SessionName.zip"} -ArgumentList $FilePath, $SessionName
    Expand-Archive -LiteralPath "$FilePath\$SessionName.zip" -DestinationPath $FilePath -Force
    Remove-Item -LiteralPath "$FilePath\$SessionName.zip"
}

# Creating combined files from all extracted blg files which was copied from remote sessions
Write-Host "Creating combined BLG files..." -ForegroundColor Yellow
$blgFiles = "$FilePath\*.blg"
$CombinedBLG = "$FilePath\CombinedFile.blg"
$CombineBLG = @($blgFiles, '-f', 'bin', '-o', $CombinedBLG)
& 'relog.exe' $CombineBLG
Write-Host "$CombinedBLG file has been created successfully" -ForegroundColor Green
Remove-Item "$FilePath\WinRM*.blg" 

# Removes all active PowerShell sessions
Write-Host "Removing all remote sessions..." -ForegroundColor Yellow
Get-PSSession | Remove-PSSession

# Posting message to Slack
$postSlackMessage = @{token="$token";channel="#homework";text="Script is finished";username="postbot"}
Invoke-RestMethod -Uri https://slack.com/api/chat.postMessage -Body $postSlackMessage

Write-Host "Script ended." -ForegroundColor Magenta

