function sync_SQL_jobs
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
    [bool]$Debug = $false
    if($PSBoundParameters.ContainsKey('Debug') -and $PSBoundParameters.Debug.Equals($true)) { [bool]$Debug = $true }
    $Script = $MyInvocation.MyCommand.Name
    if ([String]::IsNullOrEmpty($Script)) {
        $Script = 'sync_SQL_jobs.ps1'
    }
    $callStack = Get-PSCallStack
    $cmdCallStack = ($callStack[1..0]).Command -join ' => '

    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Processing ($primary_server ~ $dr_server)$(if($Debug){" in DEBUG mode"}).." | Tee-Object $LogFile -Append | Write-Output
    
    $filename = "HadrSync__"+$($Script.Replace('.ps1',''))+"__"+$primary_server.Replace('/', '_') + "__ScriptOut__$Dtmm.sql"
    $outfile = Join-Path -Path $OutputPath -ChildPath $filename

    [System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO') | out-null
    $smoprod = New-Object ('Microsoft.SqlServer.Management.Smo.Server') $primary_server
    $smodr = New-Object ('Microsoft.SqlServer.Management.Smo.Server') $dr_server

    # 01 - Sync job categories
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Find job categories.." | Tee-Object $LogFile -Append | Write-Output
    $tsqlGetCategories = @"
select name
		,[tsql_add] = 'EXEC msdb.dbo.sp_add_category @class=N'''+(case c.category_class when 1 then 'JOB' when 2 then 'ALERT' when 3 then 'Operator' else null end) 
						+''', @type=N'''+(case c.category_type when 1 then 'LOCAL' when 2 then 'MULTISERVER' when 3 then 'NONE' else null end)+''', @name=N'''+c.name+''';'
from msdb.dbo.syscategories c;
"@
    $prod_categories = @()
    $prod_categories += ExecuteQuery -SqlInstance $primary_server -Query $tsqlGetCategories -Database 'msdb';
    $dr_categories = @()
    $dr_categories += ExecuteQuery -SqlInstance $dr_server -Query $tsqlGetCategories -Database 'msdb';

    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Compare job categories.." | Tee-Object $LogFile -Append | Write-Output
    $missing_categories = @()
    $missing_categories += (Compare-Object -CaseSensitive -ReferenceObject $prod_categories -DifferenceObject $dr_categories -Property name | where-object { $_.SideIndicator -eq "<=" })
    
    if ($missing_categories.Count -gt 0)
    {
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => $($missing_categories.Count) missing job categories found." | Tee-Object $LogFile -Append | Write-Output
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Scriptout missing job categories$(if(-not $WhatIf){' and create on DR'}).." | Tee-Object $LogFile -Append | Write-Output
        $prod_categories_missing = @()
        $prod_categories_missing += $prod_categories | Where-Object {$_.name -cin $missing_categories.name}
        foreach ($catg in $prod_categories_missing)
        {
            $catg_def = $catg.tsql_add
            #$catg_def = $catg_def -ireplace ("SET ANSI_NULLS ON|SET QUOTED_IDENTIFIER ON|SET QUOTED_IDENTIFIER OFF|SET ANSI_NULLS OFF", "")
            if ($OutputPath) { $catg_def + "`rGO`r" | Out-File -Append -filepath $outfile  -ErrorAction stop }

            if (-not $WhatIf) {
                ExecuteNonQuery -SqlInstance $dr_server -Query $catg_def -Database 'msdb';
            }
        }

        if ($WhatIf) {
            "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Missing job categories scripted out in below file..`n'$outfile'" | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
        }
    }

    # 02 - Sync operators
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Find job operators.." | Tee-Object $LogFile -Append | Write-Output
    $tsqlGetOperators = @"
select o.name, o.email_address
		,[tsql_add] = 'EXEC msdb.dbo.sp_add_operator @name = N'''+o.name
								+''', @email_address = '+(case when o.email_address is not null then N''''+o.email_address+'''' else 'NULL' end)
								+', @pager_address = '+(case when o.pager_address is not null then N''''+o.pager_address+'''' else 'NULL' end) +';'
from msdb.dbo.sysoperators o;
"@
    $prod_operators = @()
    $prod_operators += ExecuteQuery -SqlInstance $primary_server -Query $tsqlGetOperators -Database 'msdb';
    $dr_operators = @()
    $dr_operators += ExecuteQuery -SqlInstance $dr_server -Query $tsqlGetOperators -Database 'msdb';

    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Compare job operators.." | Tee-Object $LogFile -Append | Write-Output
    $missing_operators = @()
    $missing_operators += (Compare-Object -CaseSensitive -ReferenceObject $prod_operators -DifferenceObject $dr_operators -Property name | where-object { $_.SideIndicator -eq "<=" })
    
    if ($missing_operators.Count -gt 0)
    {
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => $($missing_operators.Count) missing job operators found." | Tee-Object $LogFile -Append | Write-Output
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Scriptout missing job operators$(if(-not $WhatIf){' and create on DR'}).." | Tee-Object $LogFile -Append | Write-Output
        $prod_operators_missing = @()
        $prod_operators_missing += $prod_operators | Where-Object {$_.name -cin $missing_operators.name}
        foreach ($oper in $prod_operators_missing)
        {
            $oper_def = $oper.tsql_add
            #$catg_def = $catg_def -ireplace ("SET ANSI_NULLS ON|SET QUOTED_IDENTIFIER ON|SET QUOTED_IDENTIFIER OFF|SET ANSI_NULLS OFF", "")
            if ($OutputPath) { $oper_def + "`rGO`r" | Out-File -Append -filepath $outfile  -ErrorAction stop }

            if (-not $WhatIf) {
                ExecuteNonQuery -SqlInstance $dr_server -Query $oper_def -Database 'msdb';
            }
        }

        if ($WhatIf) {
            "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Missing job operators scripted out in below file..`n'$outfile'" | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
        }
    }

    # 03 - Sync Missing jobs
    <# As per discussion with Vikas, some job properties could be deliberately different b/w Prod & DR. Example, Enabled state #>
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Find agent jobs.." | Tee-Object $LogFile -Append | Write-Output
    $tsqlGetJobs = @"
select distinct j.name, j.enabled, 
		c.name as category
from msdb.dbo.sysjobs_view j
join msdb.dbo.syscategories c on c.category_id = j.category_id
where c.name not like 'REPL%'
--and c.name in ('(dba) Enable Always','(dba) Enable in PROD and During DR')
"@
    $prod_jobs = @()
    $prod_jobs += ExecuteQuery -SqlInstance $primary_server -Query $tsqlGetJobs -Database 'msdb';
    $dr_jobs = @()
    $dr_jobs += ExecuteQuery -SqlInstance $dr_server -Query $tsqlGetJobs -Database 'msdb';

    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Compare agent jobs.." | Tee-Object $LogFile -Append | Write-Output
    $missing_jobs = @()
    $missing_jobs += (Compare-Object -CaseSensitive -ReferenceObject $prod_jobs -DifferenceObject $dr_jobs -Property name | where-object { $_.SideIndicator -eq "<=" }) | Select-Object -ExpandProperty name -Unique
    
    if ($missing_jobs.Count -gt 0)
    {
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => $($missing_jobs.Count) missing job(s) found." | Tee-Object $LogFile -Append | Write-Output
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Scriptout missing job(s)$(if(-not $WhatIf){' and create on DR'}).." | Tee-Object $LogFile -Append | Write-Output
        $prod_jobs_missing = @()
        $prod_jobs_missing += $prod_jobs | Where-Object {$_.name -cin $missing_jobs} | Select-Object name, category -Unique
        foreach ($job in $prod_jobs_missing)
        {
            $jobName = $job.name
            $jobCategory = $job.category
            $job_def = ($smoprod.JobServer.Jobs[$jobName]).Script()

            # replace 01
            $job_def = $job_def -ireplace "@schedule_uid=N.+","@schedule_uid=@schedule_uid"
            # replace 02
            $job_def = $job_def -ireplace ("EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule", "declare @schedule_uid uniqueidentifier;
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule")
            if($jobCategory -ceq '(dba) Enable in PROD and During DR') {
                $job_def = $job_def + "`rEXEC msdb.dbo.sp_update_job @job_name = N'$jobName', @enabled = 0;"
            }
            
            $job_def + "`rGO`r" | Out-File -Append -filepath $outfile  -ErrorAction stop

            if (-not $WhatIf) {
                ExecuteNonQuery -SqlInstance $dr_server -Query $job_def -Database 'msdb';
            }
        }

        if ($WhatIf) {
            "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Missing jobs scripted out in below file..`n'$outfile'" | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
        }
    }

    # 04 - Sync Changed jobs
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Sync changed agent jobs.." | Tee-Object $LogFile -Append | Write-Output
    $prod_jobs_filtered = @()
    $prod_jobs_filtered += $prod_jobs | Where-Object {$_.name -cnotin $missing_jobs -and $_.enabled -eq 1 }
    $prod_jobs_changed = @()
    if ($prod_jobs_filtered.Count -gt 0)
    {
        #$job = $prod_jobs_filtered | ? {$_.name -eq 'Database Mirroring Monitor Job'}
        foreach ($job in $prod_jobs_filtered)
        {
            $jobName = $job.name
            $jobCategory = $job.category
            $job_def_prod = ($smoprod.JobServer.Jobs[$jobName]).Script()
            $job_def_dr = ($smodr.JobServer.Jobs[$jobName]).Script()

            $job_def_prod_str = $job_def_prod | Out-String
            $job_def_dr_str = $job_def_dr | Out-String
            
            # Based on category, check for enabled state of job
            if($jobCategory -ceq '(dba) Enable in PROD and During DR' -and $job_def_prod_str -cne $job_def_dr_str ) {
                $index = $job_def_dr_str.IndexOf('@enabled=0')
                $job_def_dr_str = $job_def_dr_str.Remove($index,10).Insert($index,'@enabled=1')
            }

            # replace @schedule_id guid value
            if($job_def_prod_str -cne $job_def_dr_str ) {
                $job_def_prod_str = $job_def_prod_str -creplace "@schedule_uid=N'[a-z0-9\-]*'", "@schedule_uid=N'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'"
                $job_def_dr_str = $job_def_dr_str -creplace "@schedule_uid=N'[a-z0-9\-]*'", "@schedule_uid=N'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'"
            }

            #$job_def_prod_str | Out-File -FilePath $MDS_LogsPath\prod_job.sql
            #$job_def_dr_str | Out-File -FilePath $MDS_LogsPath\dr_job.sql

            $job_def_prod_hash = $job_def_prod_str.GetHashCode()
            $job_def_dr_hash = $job_def_dr_str.GetHashCode()
            
            $has_changed = $true
            if($job_def_prod_str -ceq $job_def_dr_str) {
                $has_changed = $false
            }

            if($has_changed)
            {
                $prod_jobs_changed += $jobName;
                # replace 01
                $job_def = $job_def_prod -ireplace "@schedule_uid=N.+","@schedule_uid=@schedule_uid"
                
                # replace 02
                $job_def = $job_def -ireplace ("EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule", "declare @schedule_uid uniqueidentifier;
    EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule")
                if($jobCategory -ceq '(dba) Enable in PROD and During DR') {
                    $job_def = $job_def + "`rEXEC msdb.dbo.sp_update_job @job_name = N'$jobName', @enabled = 0;"
                }
                $job_def = "EXEC msdb.dbo.sp_delete_job @job_name=N'$jobName', @delete_unused_schedule=1;`r`r" + $job_def

                # 03 - If description missing, and modify prod & dr with dummy description due to bug in SQL Server 2019
                if($job_def -notmatch "@description=+") {
                    $job_def = $job_def + "`nEXEC msdb.dbo.sp_update_job @job_name='$jobName', @description=N'';"
                }
            
                $job_def + "`rGO`r" | Out-File -Append -filepath $outfile  -ErrorAction stop
                #$job_def + "`rGO`r" | Out-File -filepath $outfile  -ErrorAction stop

                if (-not $WhatIf) {
                    ExecuteNonQuery -SqlInstance $dr_server -Query $job_def -Database 'msdb';
                }
            }
        }

        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => $($prod_jobs_changed.Count) changed job(s) found." | Tee-Object $LogFile -Append | Write-Output
        if ($WhatIf) {
            "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Jobs scripted out in below file..`n'$outfile'" | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
        }
    }

    
    # 05 - Sync Missing SQL Agent Alerts
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Find agent alerts.." | Tee-Object $LogFile -Append | Write-Output
    $tsqlGetAlerts = @"
select [tsql_add] = 'EXEC msdb.dbo.sp_add_alert @name=N'''+a.name+''', 
		@message_id='+convert(varchar,a.message_id)+', 
		@severity='+convert(varchar,a.severity)+', 
		@enabled='+convert(varchar,a.enabled)+', 
		@delay_between_responses='+convert(varchar,a.delay_between_responses)+', 
		@include_event_description_in='+convert(varchar,a.include_event_description)+', 
		@category_name=N'''+c.name+''', '+char(10)+
		(case when a.database_name is not null then '		@wmi_namespace=N'''+ISNULL(a.database_name,'')+''',' +char(10) else '' end) +
		(case when a.database_name is not null then '		@wmi_query=N'''+ISNULL(a.performance_condition,'')+''',' +char(10) else '' end) +
		(case when a.database_name is null then '		@performance_condition=N'''+ISNULL(a.performance_condition,'')+''',' +char(10) else '' end) +
		'		@job_name=N'''+j.name+''';'
		--,*
		,a.name, a.enabled, c.name as category, j.name as job_name, a.database_name, a.performance_condition
from msdb.dbo.sysalerts a
left join msdb.dbo.syscategories c
on c.category_id = a.category_id
left join msdb.dbo.sysjobs_view j
on j.job_id = a.job_id
WHERE a.enabled = 1
"@
    $prod_alerts = @()
    $prod_alerts += ExecuteQuery -SqlInstance $primary_server -Query $tsqlGetAlerts -Database 'msdb';
    $dr_alerts = @()
    $dr_alerts += ExecuteQuery -SqlInstance $dr_server -Query $tsqlGetAlerts -Database 'msdb';

    #$smoprod.JobServer.Alerts['(dba) Blocked Process Threshold'].Script()

    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Compare agent jobs.." | Tee-Object $LogFile -Append | Write-Output
    $missing_alerts = @()
    $missing_alerts += (Compare-Object -CaseSensitive -ReferenceObject $prod_alerts -DifferenceObject $dr_alerts -Property name | where-object { $_.SideIndicator -eq "<=" }) | Select-Object -ExpandProperty name -Unique
    
    if ($missing_alerts.Count -gt 0)
    {
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => $($missing_alerts.Count) missing agent alert(s) found." | Tee-Object $LogFile -Append | Write-Output
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Scriptout missing agent alert(s)$(if(-not $WhatIf){' and create on DR'}).." | Tee-Object $LogFile -Append | Write-Output

        $missing_alerts_prod = @()
        $missing_alerts_prod += $prod_alerts | Where-Object {$_.name -cin $missing_alerts}
        foreach ($alert in $missing_alerts_prod)
        {
            $alert_def = $alert.tsql_add
            if ($OutputPath) { $alert_def + "`rGO `r " | Out-File -Append -filepath $outfile  -ErrorAction stop }

            if (-not $WhatIf) {
                ExecuteNonQuery -SqlInstance $dr_server -Query $alert_def -Database 'msdb';
            }
        }

        if ($WhatIf) {
            "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Missing agent alert(s) scripted out in below file..`n'$outfile'" | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
        }
    }

    # 06 - Sync Changed SQL Agent Alerts
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Sync changed alerts.." | Tee-Object $LogFile -Append | Write-Output

    $prod_alerts_hashes = @()
    $prod_alerts_hashes += $prod_alerts | Select-Object name, @{l='hash_id';e={$_.tsql_add.GetHashCode()}},tsql_add

    $dr_alerts_hashes = @()
    $dr_alerts_hashes += $dr_alerts | Select-Object name, @{l='hash_id';e={$_.tsql_add.GetHashCode()}},tsql_add

    $changed_alerts_comparision = @()
    $changed_alerts_comparision += Compare-Object -CaseSensitive -ReferenceObject $prod_alerts_hashes -DifferenceObject $dr_alerts_hashes -Property name, hash_id | 
                                    where-object { $_.SideIndicator -eq "<=" -and ($missing_alerts.Count -eq 0 -or $_.name -cnotin $missing_alerts) }
    if ($changed_alerts_comparision.Count -gt 0)
    {
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => $($changed_alerts_comparision.Count) changed job alert(s) found." | Tee-Object $LogFile -Append | Write-Output
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Scriptout changed job alert(s)$(if(-not $WhatIf){' and apply on DR'}).." | Tee-Object $LogFile -Append | Write-Output
        
        $changed_alerts_prod = @()
        $changed_alerts_prod += $prod_alerts | Where-Object {$_.name -cin ($changed_alerts_comparision.name)}
        foreach ($alert in $changed_alerts_prod)
        {
            $alert_def = $alert.tsql_add
            $alert_def = "EXEC msdb.dbo.sp_delete_alert @name=N'$($alert.name)';`r" + $alert_def
            if ($OutputPath) { $alert_def + "`rGO `r " | Out-File -Append -filepath $outfile  -ErrorAction stop }

            if (-not $WhatIf) {
                ExecuteNonQuery -SqlInstance $dr_server -Query $alert_def -Database 'msdb';
            }
        }
    }

    if($WhatIf) {
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => TSQL Output scripted out in below file..`n'$outfile'" | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
    }
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(FINISH)", "$cmdCallStack => Completed on ($primary_server ~ $dr_server)." | Tee-Object $LogFile -Append | Write-Output
}