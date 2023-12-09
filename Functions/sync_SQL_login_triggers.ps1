function sync_SQL_login_triggers
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
        $Script = 'sync_SQL_login_triggers.ps1'
    }
    $callStack = Get-PSCallStack
    $cmdCallStack = ($callStack[1..0]).Command -join ' => '

    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Processing ($primary_server ~ $dr_server)$(if($Debug){" in DEBUG mode"}).." | Tee-Object $LogFile -Append | Write-Output

    $filename = "HadrSync__"+$($Script.Replace('.ps1',''))+"__"+$primary_server.Replace('/', '_') + "__ScriptOut__$Dtmm.sql"
    $outfile = Join-Path -Path $OutputPath -ChildPath $filename

    [System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO') | out-null
    $smoprod = New-Object ('Microsoft.SqlServer.Management.Smo.Server') $primary_server
    $smodr = New-Object ('Microsoft.SqlServer.Management.Smo.Server') $dr_server

    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Check dependent objects on $dr_server.." | Tee-Object $LogFile -Append | Write-Output
    $sqlCheckDRObjects = @"
select [object_name] = 'master..sp__dbspace', [is_present] = count(1) from master..sysobjects where name='sp__dbspace'
union all
select [object_name] = 'DBA.._hist_sysprocesses', [is_present] = count(1) from DBA..sysobjects where name = '_hist_sysprocesses';
"@
    $resultCheckDRObjects = @()
    $resultCheckDRObjects += ExecuteQuery -SqlInstance $dr_server -Query $sqlCheckDRObjects;
    $resultCheckDRObjects_NotPresent = @()
    $resultCheckDRObjects_NotPresent += $resultCheckDRObjects | Where-Object {$_.is_present -eq 0}

    if($resultCheckDRObjects_NotPresent.Count -gt 0) {
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(WARN)", "$cmdCallStack => Dependent objects not found on $dr_server.." | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Magenta
        $resultCheckDRObjects_NotPresent | Format-Table -AutoSize | Out-String | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Magenta

        $Body = "The following objects are dependency for logon triggers for ($primary_server ~ $dr_server) -`n`n $( $resultCheckDRObjects_NotPresent | Format-Table -AutoSize | Out-String )`n`n";
        $Body = $body + "Kindly create all the dependent objects related to login triggers.`n"
        $Body = $body + "-- Alert generated from HadrSync Module.`n"
        $message = $Body

        if(-not $WhatIf) {
            Raise-DbaServiceNowAlert -Summary "HadrSync-sync_SQL_login_triggers-$primary_server" -Severity HIGH -Description $message `
                                -AlertSourceHost $primary_server -AlertTargetHost $primary_server `
                                -Alertkb $alertKB
        }
        else {
            "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(WARN)", "$cmdCallStack => `n$message" | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Magenta
        }

        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(WARN)", "$cmdCallStack => Kindly create above dependent objects on $dr_server.." | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Magenta
        return
    }

    
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Compare hash of all Triggers.." | Tee-Object $LogFile -Append | Write-Output
    $sqlTriggers = @"
select t.name, t.parent_class_desc, t.type_desc, t.create_date, t.modify_date, t.is_ms_shipped, t.is_disabled 
		,master.sys.fn_repl_hash_binary(convert(varbinary(max),ltrim(rtrim(OBJECT_DEFINITION(t.object_id))))) as hash_id
from sys.server_triggers t
where t.type_desc = 'SQL_TRIGGER' and t.parent_class_desc = 'SERVER'
--and t.name = 'audit_login_events'
"@
    $triggersProd = @()
    $triggersProd += ExecuteQuery -SqlInstance $primary_server -Query $sqlTriggers;
    $triggersDR = @()
    $triggersDR += ExecuteQuery -SqlInstance $dr_server -Query $sqlTriggers;

    # Get missing Procedures in DR
    $missing_triggers = @()
    $missing_triggers += (Compare-Object -CaseSensitive -ReferenceObject $triggersProd -DifferenceObject $triggersDR -Property name | where-object { $_.SideIndicator -eq "<=" })    

    
    # Sync missing Logon Triggers
    if ($missing_triggers.Count -gt 0)
    {
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => $($missing_triggers.Count) missing server trigger(s) found." | Tee-Object $LogFile -Append | Write-Output
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Scriptout missing server trigger(s)$(if(-not $WhatIf){' and apply on DR'}).." | Tee-Object $LogFile -Append | Write-Output
        foreach ($tgr in $missing_triggers)
        {
            $tgr_def = ($smoprod.Triggers[$tgr.name]).Script()         
            $tgr_def = $tgr_def -ireplace ("SET ANSI_NULLS ON|SET QUOTED_IDENTIFIER ON|SET QUOTED_IDENTIFIER OFF|SET ANSI_NULLS OFF", "")
            
            if ($OutputPath) {
                "/* Missing Trigger */ `n$tgr_def" + "`rGO `r " | Out-File -Append -filepath $outfile -ErrorAction stop
            }

            if (-not $WhatIf) {
                if($tgr_def.IndexOf("ENABLE TRIGGER [$($tgr.name)] ON ALL SERVER") -gt 0) {
                    $enabled = $true
                    $tgr_def = $tgr_def.replace("ENABLE TRIGGER [$($tgr.name)] ON ALL SERVER",'')
                }else {
                    $enabled = $false
                    $tgr_def = $tgr_def.replace("DISABLE TRIGGER [$($tgr.name)] ON ALL SERVER",'')
                }
                ExecuteNonQuery -SqlInstance $dr_server -Query $tgr_def -db 'master';
                if($enabled) {
                    ExecuteNonQuery -SqlInstance $dr_server -Query "ENABLE TRIGGER [$($tgr.name)] ON ALL SERVER" -db 'master';
                }
                else {
                    ExecuteNonQuery -SqlInstance $dr_server -Query "DISABLE TRIGGER [$($tgr.name)] ON ALL SERVER" -db 'master';
                }
            }
        }

        if ($WhatIf) {
            "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => missing server trigger(s) scripted out in below file..`n'$outfile'" | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
        }
    }

    # Sync changed Triggers
    $changed_triggers_prod = @()
    $changed_triggers_prod += Compare-Object -CaseSensitive -ReferenceObject $triggersProd -DifferenceObject $triggersDR -Property name, hash_id | `
                                    where-object { $_.SideIndicator -eq "<=" -and ($missing_triggers.Count -eq 0 -or $_.name -cin $($missing_triggers.name)) }
    if ($changed_triggers_prod.Count -gt 0)
    {
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => $($changed_triggers_prod.Count) changed server trigger(s) found." | Tee-Object $LogFile -Append | Write-Output
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Scriptout changed server trigger(s)$(if(-not $WhatIf){' and apply on DR'}).." | Tee-Object $LogFile -Append | Write-Output
        foreach ($tgr in $changed_triggers_prod)
        {
            $tgr_def = ($smoprod.Triggers[$tgr.name]).Script()
            $tgr_def = $tgr_def -ireplace ("SET ANSI_NULLS ON|SET QUOTED_IDENTIFIER ON|SET QUOTED_IDENTIFIER OFF|SET ANSI_NULLS OFF", "")

            $tgr_drop = "use [master]; DROP TRIGGER [$($tgr.name)] ON ALL SERVER;"
            if ($OutputPath) {
                "/* Sync Changed Trigger */ `n$tgr_drop" + "`rGO `r " | Out-File -Append -filepath $outfile -ErrorAction stop
                $tgr_def + "`rGO `r " | Out-File -Append -filepath $outfile -ErrorAction stop
            }

            if (-not $WhatIf) {
                ExecuteNonQuery -SqlInstance $dr_server -Query $tgr_drop -db 'master';
                if($tgr_def.IndexOf("ENABLE TRIGGER [$($tgr.name)] ON ALL SERVER") -gt 0) {
                    $enabled = $true
                    $tgr_def = $tgr_def.replace("ENABLE TRIGGER [$($tgr.name)] ON ALL SERVER",'')
                }else {
                    $enabled = $false
                    $tgr_def = $tgr_def.replace("DISABLE TRIGGER [$($tgr.name)] ON ALL SERVER",'')
                }
                ExecuteNonQuery -SqlInstance $dr_server -Query $tgr_def -db 'master';
                if($enabled) {
                    ExecuteNonQuery -SqlInstance $dr_server -Query "ENABLE TRIGGER [$($tgr.name)] ON ALL SERVER" -db 'master';
                }
                else {
                    ExecuteNonQuery -SqlInstance $dr_server -Query "DISABLE TRIGGER [$($tgr.name)] ON ALL SERVER" -db 'master';
                }
            }
        }

        if ($WhatIf) {
            "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Changed server trigger(s) scripted out in below file..`n'$outfile'" | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
        }
    }

    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(FINISH)", "$cmdCallStack => Completed on ($primary_server ~ $dr_server)." | Tee-Object $LogFile -Append | Write-Output
}
