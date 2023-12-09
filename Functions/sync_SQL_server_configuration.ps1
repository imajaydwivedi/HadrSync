function sync_SQL_server_configuration
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [string]$primary_server,
        [Parameter(Mandatory = $true)]
        [string]$dr_server,
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,
        [Parameter(Mandatory = $true)]
        [string]$LogFile,
        [switch]$WhatIf
    )
    # This module compares the SQL configuration on both
    # primary server and DR server and reports any differences.
    #
    # NOTE: Since there are config values which require a restart
    #       and some which are self-configuring values this module
    #       will not set any configuration value. It will just report
    #       differences. Configration values need to be modified manually

    [bool]$Debug = $false
    if($PSBoundParameters.ContainsKey('Debug') -and $PSBoundParameters.Debug.Equals($true)) { [bool]$Debug = $true }
    $Script = $MyInvocation.MyCommand.Name
    if ([String]::IsNullOrEmpty($Script)) {
        $Script = 'sync_SQL_server_configuration.ps1'
    }
    $callStack = Get-PSCallStack
    $cmdCallStack = ($callStack[1..0]).Command -join ' => '

    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Processing ($primary_server ~ $dr_server)$(if($Debug){" in DEBUG mode"}).." | Tee-Object $LogFile -Append | Write-Output

    $filename = "HadrSync__"+$($Script.Replace('.ps1',''))+"__"+$primary_server.Replace('/', '_') + "__ScriptOut__$Dtmm.sql"
    $outfile = Join-Path -Path $OutputPath -ChildPath $filename
    
    #Write-Debug "Inside sync_SQL_server_configuration"
    #return

    # Get single word Prod server name
    if ($primary_server.Toupper().contains(".WIN.lab.com")) { $primary = $primary_server.Toupper().replace(".WIN.lab.com", "") }
    elseif ($primary_server.contains("\")) { $primary = $primary_server.substring($primary_server.IndexOf("\") + 1) }
    else { $primary = $primary_server }

    # Get single word DR server name
    if ($dr_server.Toupper().contains(".WIN.lab.com")) { $dr = $dr_server.Toupper().replace(".WIN.lab.com", "") }
    elseif ($dr_server.contains("\")) { $dr = $dr_server.replace("\", "_") }
    else { $dr = $dr_server }

    # Drop temp tables
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Drop temp tables on $dr_server.." | Tee-Object $LogFile -Append | Write-Output
    $sqlDropTempTables = @"
if exists (select * from sandbox..sysobjects where name = 'sys_config_$primary')
    exec ('drop table sandbox..sys_config_$primary');
if exists (select * from sandbox..sysobjects where name = 'sys_config_$dr') 
    exec ('drop table sandbox..sys_config_$dr')
"@
    ExecuteNonQuery -SqlInstance $dr_server -Query $sqlDropTempTables

    # Create Temp tables with config details
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Create temp tables with config details on $dr_server.." | Tee-Object $LogFile -Append | Write-Output
    $sqlCreateTempTables = @"
select * into sandbox..sys_config_$primary from $primary.master.sys.configurations;
select * into sandbox..sys_config_$dr from sys.configurations;
"@
    ExecuteNonQuery -SqlInstance $dr_server -Query $sqlCreateTempTables

    # Sync diff changes
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Find config differences.." | Tee-Object $LogFile -Append | Write-Output
    $sqlConfigChanges = @"
IF OBJECT_ID('DBA..DR_server_config_alert_exclusions') IS NULL
EXEC ('CREATE TABLE DBA.[dbo].[DR_server_config_alert_exclusions]( [config_name] [nvarchar](35) NOT NULL, [reason_for_exclusion] [varchar](200) NOT NULL, [dba_request] [char](10) NOT NULL );');

select [primary].name,
		[primary_value_in_use] = convert(varchar(20),[primary].value_in_use), 
		[dr_value_in_use] = convert(varchar(20),dr.value_in_use)
from sandbox..sys_config_$primary [primary]
join sandbox..sys_config_$dr dr on [primary].name=dr.name
where [primary].value_in_use != dr.value_in_use
and [primary].name not in (select config_name from DBA..DR_server_config_alert_exclusions)
"@
    $discrepancy_srv_settings = @()
    $discrepancy_srv_settings += ExecuteQuery -SqlInstance $dr_server -Query $sqlConfigChanges

    # Generate ServiceNow Here
    if ($discrepancy_srv_settings.Count -gt 0)
    {
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(WARNING)", "$cmdCallStack => Following config are different b/w Prod & Dr -" | Tee-Object $LogFile -Append | Write-Host -ForegroundColor DarkRed -BackgroundColor Yellow
        $discrepancy_srv_settings | Sort-Object -Property name | Format-Table -AutoSize | Out-String -Width 4096 | Tee-Object $LogFile -Append | Write-Host -ForegroundColor DarkRed -BackgroundColor Yellow

        $result = $discrepancy_srv_settings | sort-object -Property name | Format-Table -AutoSize | Out-String
        $result | Tee-Object $outfile -Append | Out-Null

        $Body = "Following config are different b/w Prod & Dr -`n";
        $Body = $Body + $result;
        $Body = $Body + "`n`nKindly take corrective Action`n"
		$Body = $Body + "-- Alert generated from HadrSync Module.`n"
        $message = $Body

        if(-not $WhatIf) {
            Raise-DbaServiceNowAlert -Summary "HadrSync-ServerConfig-$primary_server" -Severity HIGH -Description $message `
                            -AlertSourceHost $primary_server -AlertTargetHost $primary_server `
                            -Alertkb $alertKB
        }
        else {
            "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(WARN)", "$cmdCallStack => `n$message" | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Magenta
        }

        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(WARNING)", "$cmdCallStack => Please update the configurations on DR server manually" | Tee-Object $LogFile -Append | Write-Host -ForegroundColor DarkRed -BackgroundColor Yellow
    }
    else {
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => No config diff found." | Tee-Object $LogFile -Append | Write-Output
    }
    
    if($WhatIf) {
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => TSQL Output scripted out in below file..`n'$outfile'" | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
    }
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(FINISH)", "$cmdCallStack => Completed on ($primary_server ~ $dr_server)." | Tee-Object $LogFile -Append | Write-Output
}
