function sync_SQL_linked_server {
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
    [bool]$Debug = $false
    if ($PSBoundParameters.ContainsKey('Debug') -and $PSBoundParameters.Debug.Equals($true)) { [bool]$Debug = $true }
    $Script = $MyInvocation.MyCommand.Name
    if ([String]::IsNullOrEmpty($Script)) {
        $Script = 'sync_SQL_linked_server.ps1'
    }
    $callStack = Get-PSCallStack
    $cmdCallStack = ($callStack[1..0]).Command -join ' => '

    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Processing ($primary_server ~ $dr_server)$(if($Debug){" in DEBUG mode"}).." | Tee-Object $LogFile -Append | Write-Output

    $filename = "HadrSync__" + $($Script.Replace('.ps1', '')) + "__" + $primary_server.Replace('/', '_') + "__ScriptOut__$Dtmm.sql"
    $outfile = Join-Path -Path $OutputPath -ChildPath $filename
    
    # module to alert if there are differences in the linked servers
    # Note: As the password embeded in linked servers cannot be
    #       determined, we are alerting if there is a difference in
    #       configuration for linked servers. However a difference in
    #       passwords cannot be determined
    
    # Get single word prod server name
    if ($primary_server.Toupper().contains(".WIN.lab.com")) { $primary = $primary_server.Toupper().replace(".WIN.lab.com", "") }
    elseif ($primary_server.Toupper().contains(".lab.com")) { $primary = $primary_server.substring(0, $primary_server.IndexOf(".")) }
    elseif ($primary_server.contains("\")) { $primary = $primary_server.substring($primary_server.IndexOf("\") + 1) }
    else { $primary = $primary_server }
    
    # Get single word dr server name
    if ($dr_server.Toupper().contains(".WIN.lab.com")) { $dr = $dr_server.Toupper().replace(".WIN.lab.com", "") }
    elseif ($dr_server.Toupper().contains(".lab.com")) { $dr = $dr_server.substring(0, $dr_server.IndexOf(".")) }
    elseif ($dr_server.contains("\")) { $dr = $dr_server.replace("\", "_") }
    else { $dr = $dr_server }

    # Prepare sys.servers of Prod on DR
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Query/Save sys.servers on $primary_server into sandbox..sys_servers_$primary.." | Tee-Object $LogFile -Append | Write-Output
    $sql = "if exists (select * from sandbox..sysobjects where name = 'sys_servers_$primary') drop table sandbox..sys_servers_$primary;
select * into sandbox..sys_servers_$primary from $primary.master.sys.servers;"
    invoke-sqlcmd -ServerInstance $dr_server -Database master -Query $sql

    # Prepare sys.servers of DR on Dr
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Query/Save sys.servers on $dr_server into sandbox..sys_servers_$primary.." | Tee-Object $LogFile -Append | Write-Output
    $sql = "if exists (select * from sandbox..sysobjects where name = 'sys_servers_$dr') drop table sandbox..sys_servers_$dr;
select * into sandbox..sys_servers_$dr from sys.servers;"
    ExecuteNonQuery -SqlInstance $dr_server -Query $sql

    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Finding missing Linked Servers.." | Tee-Object $LogFile -Append | Write-Output
    $sql = "select name from sandbox..sys_servers_$primary where name not in (select name from sandbox..sys_servers_$dr) and server_id != 0 and name != 'repl_distributor' and left(name,1) <> '['"
    $missing_server_list = @()
    $missing_server_list += ExecuteQuery -SqlInstance $dr_server -Query $sql
    #Alert missing linked servers

    # Generate ServiceNow Here
    if ($missing_server_list.Count -gt 0) {
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(WARNING)", "$cmdCallStack => Following missing Linked Servers found-" | Tee-Object $LogFile -Append | Write-Host -ForegroundColor DarkRed -BackgroundColor Yellow
        $missing_server_list.name | Tee-Object $LogFile -Append | Write-Host -ForegroundColor DarkRed -BackgroundColor Yellow

        $Body = "The following linked servers not found on DR for ($primary_server ~ $dr_server) -`n`n $( ($missing_server_list.name) -join ', ' )`n`n";
        $Body = $body + "Kindly take corrective action.`n"
        $Body = $body + "-- Alert generated from HadrSync Module.`n"
        $message = $Body

        if(-not $WhatIf) {
            Raise-DbaServiceNowAlert -Summary "HadrSync-LinkedServerMissing-$primary_server" -Severity HIGH -Description $message `
                                -AlertSourceHost $primary_server -AlertTargetHost $primary_server `
                                -Alertkb $alertKB
        }
        else {
            "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(WARN)", "$cmdCallStack => `n$message" | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Magenta
        }

        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(WARNING)", "$cmdCallStack => Manually create these linked Server on $dr_server" | Tee-Object $LogFile -Append | Write-Host -ForegroundColor DarkRed -BackgroundColor Yellow
    }
    else {
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => No missing Linked Servers found." | Tee-Object $LogFile -Append | Write-Output
    }

    #sync non-password specific server configurations for existing servers
    $sql = @"
select server_id,
        name,
        product,
        data_source,
        location,
        provider_string,
        catalog,
        connect_timeout,
        query_timeout,
        is_linked,
        is_remote_login_enabled,
        is_rpc_out_enabled,
        is_data_access_enabled,
        is_collation_compatible,
        uses_remote_collation,
        collation_name,
        lazy_schema_validation,
        is_system,is_publisher,
        is_subscriber,
        is_distributor,
        is_nonsql_subscriber,
        is_remote_proc_transaction_promotion_enabled 
from sandbox..sys_servers_$primary
where server_id != 0 and name != 'repl_distributor' and name in (select name from sandbox..sys_servers_$dr)
"@
    $primary_server_configuration = @()
    $primary_server_configuration += ExecuteQuery -SqlInstance $dr_server -Query $sql

    if ($primary_server_configuration.Count -gt 0)
    {
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Sync All Linked Server properties.." | Tee-Object $LogFile -Append | Write-Output
        foreach ($srv in $primary_server_configuration)
        {
            $sql1 = "EXEC master.dbo.sp_serveroption @server=N'" + $srv.name + "', @optname=N'collation compatible', @optvalue=N'" + $(if ($srv.is_collation_compatible -eq 1) { $("true';") } else { $("false';") }) + "`n" + "" + "`n"
            $sql1 = $sql1 + "EXEC master.dbo.sp_serveroption @server=N'" + $srv.name + "', @optname=N'data access', @optvalue=N'" + $(if ($srv.is_data_access_enabled -eq 1) { $("true';") } else { $("false';") }) + "`n" + "" + "`n"
            $sql1 = $sql1 + "EXEC master.dbo.sp_serveroption @server=N'" + $srv.name + "', @optname=N'dist', @optvalue=N'" + $(if ($srv.is_distributor -eq 1) { $("true';") } else { $("false';") }) + "`n" + "" + "`n"
            $sql1 = $sql1 + "EXEC master.dbo.sp_serveroption @server=N'" + $srv.name + "', @optname=N'pub', @optvalue=N'" + $(if ($srv.is_publisher -eq 1) { $("true';") } else { $("false';") }) + "`n" + "" + "`n"
            $sql1 = $sql1 + "EXEC master.dbo.sp_serveroption @server=N'" + $srv.name + "', @optname=N'rpc', @optvalue=N'" + $(if ($srv.is_remote_login_enabled -eq 1) { $("true';") } else { $("false';") }) + "`n" + "" + "`n"
            $sql1 = $sql1 + "EXEC master.dbo.sp_serveroption @server=N'" + $srv.name + "', @optname=N'rpc out', @optvalue=N'" + $(if ($srv.is_rpc_out_enabled -eq 1) { $("true';") } else { $("false';") }) + "`n" + "" + "`n"
            $sql1 = $sql1 + "EXEC master.dbo.sp_serveroption @server=N'" + $srv.name + "', @optname=N'sub', @optvalue=N'" + $(if ($srv.is_subscriber -eq 1) { $("true';") } else { $("false';") }) + "`n" + "" + "`n"
            $sql1 = $sql1 + "EXEC master.dbo.sp_serveroption @server=N'" + $srv.name + "', @optname=N'connect timeout', @optvalue=N'" + $srv.connect_timeout + "'`n" + "" + "`n"
            $sql1 = $sql1 + "EXEC master.dbo.sp_serveroption @server=N'" + $srv.name + "', @optname=N'lazy schema validation', @optvalue=N'" + $(if ($srv.lazy_schema_validation -eq 1) { $("true';") } else { $("false';") }) + "`n" + "" + "`n"
            $sql1 = $sql1 + "EXEC master.dbo.sp_serveroption @server=N'" + $srv.name + "', @optname=N'query timeout', @optvalue=N'" + $srv.query_timeout + "'`n" + "" + "`n"
            $sql1 = $sql1 + "EXEC master.dbo.sp_serveroption @server=N'" + $srv.name + "', @optname=N'use remote collation', @optvalue=N'" + $(if ($srv.uses_remote_collation -eq 1) { $("true';") } else { $("false';") }) + "`n" + "" + "`n"
            $sql1 = $sql1 + "EXEC master.dbo.sp_serveroption @server=N'" + $srv.name + "', @optname=N'remote proc transaction promotion', @optvalue=N'" + $(if ($srv.is_remote_proc_transaction_promotion_enabled -eq 1) { $("true';") } else { $("false';") }) + "`n"
                                                                        
            If ($WhatIf) {
                "$sql1`nGO`n" | Tee-Object $outfile -Append | Out-Null
            }
            else {
                ExecuteNonQuery -SqlInstance $dr_server -Query $sql1
            }
        }
        
        if($WhatIf) {
            "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => TSQL Scriptout in below file..`n'$outfile'" | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
        }
    }

     
    #alert if login configuration for the linked servers varies
    $sql = "if exists (select * from sandbox..sysobjects where name = 'sys_linked_logins_$primary') drop table sandbox..sys_linked_logins_$primary;" 
    ExecuteNonQuery -SqlInstance $dr_server -Query $sql

    $sql = "select * into sandbox..sys_linked_logins_$primary from openquery($primary,'select ss.name,uses_self_credential,sp.name as local_name,remote_name
from sys.linked_logins ll 
left outer join sys.server_principals sp on ll.local_principal_id = sp.principal_id
full outer join sys.servers ss on  ll.server_id = ss.server_id 
where ll.server_id != 0 and ss.name != ''repl_distributor''')"
    ExecuteNonQuery -SqlInstance $dr_server -Query $sql

    $sql = "if exists (select * from sandbox..sysobjects where name = 'sys_linked_logins_$dr') drop table sandbox..sys_linked_logins_$dr";
    ExecuteNonQuery -SqlInstance $dr_server -Query $sql
    $sql = "select ss.name,uses_self_credential,sp.name as local_name,remote_name into sandbox..sys_linked_logins_$dr
from sys.linked_logins ll
left outer join sys.server_principals sp on ll.local_principal_id = sp.principal_id
full outer join sys.servers ss on  ll.server_id = ss.server_id 
where ll.server_id != 0 and ss.name != 'repl_distributor' and ss.name != '$primary'";
    ExecuteNonQuery -SqlInstance $dr_server -Query $sql
       

    $sql = "DELETE sandbox..sys_linked_logins_$primary WHERE name not in (select name from sandbox..sys_linked_logins_$dr)";
    ExecuteNonQuery -SqlInstance $dr_server -Query $sql

    $sql = "update sandbox..sys_linked_logins_$dr set local_name = '' where local_name is null;
update sandbox..sys_linked_logins_$dr set remote_name = '' where remote_name is null;";
    ExecuteNonQuery -SqlInstance $dr_server -Query $sql

    $sql = "update sandbox..sys_linked_logins_$primary set local_name = '' where local_name is null;
update sandbox..sys_linked_logins_$primary set remote_name = '' where remote_name is null;";
    ExecuteNonQuery -SqlInstance $dr_server -Query $sql


    $sql = @"
if exists ( select 1 from DBA.sys.tables where name = 'DR_linked_server_alert_exclusion_list' )
begin
	select *
	from (
		select distinct isnull(nyc.name, dr.name) as linked_server_name
		from sandbox..sys_linked_logins_$primary nyc
		full outer join sandbox..sys_linked_logins_$dr dr on nyc.name = dr.name
			and nyc.uses_self_credential = dr.uses_self_credential
			and nyc.local_name = dr.local_name
			and nyc.remote_name = dr.remote_name
		where nyc.name is null
			or dr.name is null
		) a
	where linked_server_name not in (
			select linked_server_name collate database_default
			from DBA..DR_linked_server_alert_exclusion_list
			)
	and left(linked_server_name,1) <> '['
end
else
	select *
	from (
		select distinct isnull(nyc.name, dr.name) as linked_server_name
		from sandbox..sys_linked_logins_$primary nyc
		full outer join sandbox..sys_linked_logins_$dr dr on nyc.name = dr.name
			and nyc.uses_self_credential = dr.uses_self_credential
			and nyc.local_name = dr.local_name
			and nyc.remote_name = dr.remote_name
		where (nyc.name is null
			or dr.name is null)
	) b
	where left(linked_server_name,1) <> '['
"@
    $discrepancy_config_servers = @()
    $discrepancy_config_servers += ExecuteQuery -SqlInstance $dr_server -Query $sql
    
    # Generate ServiceNow Here
    if ($discrepancy_config_servers.Count -gt 0) {
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(WARNING)", "$cmdCallStack => Following one or more Linked Servers have non-matching config -" | Tee-Object $LogFile -Append | Write-Host -ForegroundColor DarkRed -BackgroundColor Yellow
        $discrepancy_config_servers.linked_server_name | Tee-Object $LogFile -Append | Write-Host -ForegroundColor DarkRed -BackgroundColor Yellow

        $Body = "The following one or more linked servers have non-matching config b/w ($primary_server ~ $dr_server) -`n`n $( ($discrepancy_config_servers.linked_server_name) -join ', ' )`n`n";
        $Body = $body + "Kindly take corrective action.`n"
        $Body = $body + "-- Alert generated from HadrSync Module.`n"
        $message = $Body

        if(-not $WhatIf) {
            Raise-DbaServiceNowAlert -Summary "HadrSync-LinkedServerConfig-$primary_server" -Severity HIGH -Description $message `
                                -AlertSourceHost $primary_server -AlertTargetHost $primary_server `
                                -Alertkb $alertKB
        }
        else {
            "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(WARN)", "$cmdCallStack => `n$message" | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Magenta
        }

        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(WARNING)", "$cmdCallStack => Please update the configurations such that login mapping is the same on both the primary and DR server" | Tee-Object $LogFile -Append | Write-Host -ForegroundColor DarkRed -BackgroundColor Yellow
    }
    else {
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => No config diff found on Linked Servers." | Tee-Object $LogFile -Append | Write-Output
    }    
}

