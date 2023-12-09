[CmdletBinding()]
Param (    
    [Parameter(Mandatory = $true)]
    [ValidateSet("DOMAIN1","DOMAIN2")]
    $Environment,
    [Parameter(Mandatory = $false)]
    [string]$OutputPath,
    [string]$JobFailureNotifyThreshold = 2,
    [Switch]$WhatIf
)

"{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(START)", "Import required modules.." | Write-Output
if([string]::IsNullOrEmpty($PSScriptRoot)) {
    $PSScriptRoot = 'C:\Users\Public\Documents\git\dba\DOMAIN1\powershell\modules\HadrSync\Wrappers'
}
Import-Module $PsScriptRoot\..\..\DbaUtil -DisableNameChecking
Import-Module $PsScriptRoot\..\HadrSync -DisableNameChecking
$Error.Clear();
$global:ErrorMessages.Clear()

$Script = $MyInvocation.MyCommand.Name
if([String]::IsNullOrEmpty($Script)) {
    $Script = 'Wrapper-SyncMetaData.ps1'
}
[bool]$Debug = $false
if($PSBoundParameters.ContainsKey('Debug') -and $PSBoundParameters.Debug.Equals($true)) { [bool]$Debug = $true }

$logFileBaseName = "$($Script -replace '.ps1', '') - $Dtmm.txt"
if ([String]::IsNullOrEmpty($OutputPath)) {
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "No OutputPath specified." | Write-Output
    $OutputPath = "$PsScriptRoot\..\..\..\Logs\HadrSync"
    if($Environment -eq 'DOMAIN2') {
        $OutputPath = "$PsScriptRoot\..\..\..\..\Logs\HadrSync"
    }
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "Choosing default Output path '$OutputPath'." | Write-Output
}
if (-not (Test-Path -Path $OutputPath)) {
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "Create OutputPath path.." | Write-Output
    New-Item -ItemType directory -Path $OutputPath | Out-Null
}
$logFileFullPath = Join-Path -Path $OutputPath -ChildPath $logFileBaseName

"{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(START)", "Execute script '$Script'$(if($WhatIf){" with `$WhatIf"})$(if($Debug){" in DEBUG mode"}).." | Tee-Object $logFileFullPath -Append | Write-Output
"{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "`$logFileFullPath -> '$logFileFullPath'" | Tee-Object $logFileFullPath -Append | Write-Output

if (Test-Path -Path $OutputPath) {
    # Clear previous log files older than $LogRetentionDays
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "Remove logs older than `$LogRetentionDays ($LogRetentionDays).." | Tee-Object $logFileFullPath -Append | Write-Output
    Get-ChildItem -Path $(Join-Path $OutputPath "$($Script -replace '.ps1', '')*") `
        | Where-Object {$_.PSIsContainer -eq $false -and $_.LastWriteTime -lt (Get-Date).AddDays(-$LogRetentionDays) } `
        | Remove-Item -WhatIf:$WhatIf -Verbose | Tee-Object $logFileFullPath -Append | Write-Output
    Get-ChildItem -Path $(Join-Path $OutputPath "HadrSync*.sql") `
        | Where-Object {$_.PSIsContainer -eq $false -and $_.LastWriteTime -lt (Get-Date).AddDays(-$LogRetentionDays) } `
        | Remove-Item -WhatIf:$WhatIf -Verbose | Tee-Object $logFileFullPath -Append | Write-Output
}

try {
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "Executing main -WhatIf:`$$WhatIf" | Tee-Object $logFileFullPath -Append | Write-Output
    
    $tsqlServers = @"
SELECT p.Dataserver AS prod_data_server, p.FriendlyName as prod_friendly_name
	,p.DRDataserver AS dr_data_server, d.FriendlyName as dr_friendly_name
	,1 AS is_hadr_sync_enabled
FROM DbaCentral.dbo.server_inventory p
JOIN DbaCentral.dbo.server_inventory d
	ON d.Dataserver = p.DRDataserver
WHERE p.IsActive = 1
	AND p.Env = 'PROD'
	AND p.Monitor = 'Yes'
    AND p.Role = 'Primary'
	AND p.ServerType = 'DB'
	AND p.HasDR = 'Yes'
	AND p.Description $(if($Environment -eq 'DOMAIN2'){' not '}) like '%A.P. Lab & Co.%'
    AND d.Description $(if($Environment -eq 'DOMAIN2'){' not '}) like '%A.P. Lab & Co.%'
"@
    <#
    if($Environment -eq 'DOMAIN1') {
        $tsqlServers = $tsqlServers + @"

--
UNION ALL
--
SELECT 'SQLPROD6.lab.com,14346' as prod_data_server, 'SQLPROD6' as prod_friendly_name,
		'SQLDR6.lab.com,14356' as dr_data_server, 'SQLDR6' as dr_friendly_name
		,1 AS is_hadr_sync_enabled
"@
    }
    #>

    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "Fetch servers from $InventoryServer.." | Tee-Object $logFileFullPath -Append | Write-Output
    $server_list = Invoke-Sqlcmd -ServerInstance $InventoryServer -Database $InventoryDb -Query $tsqlServers -ConnectionTimeout 60 -QueryTimeout 60;

    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "Loop through each server, and initiate SyncMetaData.." | Tee-Object $logFileFullPath -Append | Write-Output
    $srvSuccess = @()
    $srvFailed = @()
    $errMessages = @()
    $server_list_filtered = @()
    $server_list_filtered += $server_list #| Where-Object {$_.prod_friendly_name -in @('SQLPROD6')}
    foreach ($server in $server_list_filtered)
    {
        $prod_server = $server.prod_data_server;
        $dr_server = $server.dr_data_server;
        $prod_name = $server.prod_friendly_name
        $dr_name = $server.dr_friendly_name

        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "Processing ($prod_name ~ $dr_name).." | Write-Host -ForegroundColor Cyan
        
        try
        {
            # Start: Check Servers Status
            $tsqlIsAvailable = "select SERVERPROPERTY('MachineName') as server_name";
            Invoke-Sqlcmd -ServerInstance $prod_name -Query $tsqlIsAvailable -ConnectionTimeout 60 -QueryTimeout 60 | Out-Null;
            Invoke-Sqlcmd -ServerInstance $dr_name -Query $tsqlIsAvailable -ConnectionTimeout 60 -QueryTimeout 60 | Out-Null;

            #if($prod_name -in @('SQLPROD12','SQLPROD6')) { 1/0 }
            
            sync_meta_data -primary_server $prod_name -dr_server $dr_name -outputpath $OutputPath -LogFile $logFileFullPath -WhatIf:$WhatIf -Debug:$Debug

            $srvSuccess += $prod_name
        }
        catch {
            # Error being saved in $global:ErrorMessages
            #$errMsgSrv = $_.ToString() + $_.InvocationInfo.PositionMessage
            #$errMsgSrv = "Failure for ($prod_name ~ $dr_name) with below error message -`n$errMsgSrv"
            #$errMessages += $errMsgSrv;
            $srvFailed += $prod_name

            #"{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(ERROR)", "$errMsgSrv" | Write-Host -ForegroundColor Red
        }
    }

    if($srvSuccess -gt 0) {
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "Script successful for below servers - ($($srvSuccess -join ', '))" | Tee-Object $logFileFullPath -Append | Write-Output        
    }
    if($srvFailed -gt 0) {
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(ERROR)", "Script failed for below servers - ($($srvFailed -join ', '))" | Tee-Object $logFileFullPath -Append | Write-Output
    }

    $endTime = Get-Date
    $durationSpan = New-TimeSpan -Start $startTime -End $endTime
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(FINISH)", "$Script completed in $([Math]::Ceiling($durationSpan.TotalMinutes)) minutes." | Tee-Object $logFileFullPath -Append | Write-Output

    if($Global:ErrorMessages.Count -gt 0) {
        throw ($Global:ErrorMessages -join "`n$('-'*60)`n")
    }
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "Validate log file '$logFileFullPath'" | Write-Host -ForegroundColor Yellow
}
catch
{
    if($Global:ErrorMessages.Count -gt 0) {
        $errMessage = $_.ToString()
    }
    else {
        $errMessage = $_.ToString() + $_.InvocationInfo.PositionMessage
    }
    $errMessage | Out-File $logFileFullPath -Append
    
    # Generate ServiceNow body text
    $Body = "Alert: HadrSync failed for $Environment`n";
    $Body = $Body + "Execution Time: $([Math]::Ceiling($durationSpan.TotalMinutes)) minutes `n";
    $Body = $Body + "View Alert Status: '(dba) Invoke-HadrSync' job on DBMONITOR `n";
    $Body = $Body + "Alert Parameters:`n";
    $Body = $Body + "Description: HadrSync failed for few servers in $Environment environment.`nPlease find logs in `"$logFileFullPath`".";
    $Body = $Body + "`nBelow are error details-`n`n$errMessage`n`n";
    $Body = $Body + "`n`nNote: A reminder email will be sent.`n";
    $Subject = "HadrSync-$Environment-Failed";

    if(-not $WhatIf) {
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "Raising ServiceNow alert.." | Write-Host -ForegroundColor Yellow
        Raise-DbaServiceNowAlert -Summary "$Subject" -Severity HIGH -Description $Body -AlertSourceHost $prod_name -AlertTargetHost $prod_name -AlertKB $alertKB -verbose    
    }
    else {
        $Body | Write-Host -ForegroundColor Yellow
    }

    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "Validate log file '$logFileFullPath'" | Write-Host -ForegroundColor Yellow
    throw $errMessage
}