function sync_auto_stats_config
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
        $Script = 'sync_auto_stats_config.ps1'
    }
    $callStack = Get-PSCallStack
    $cmdCallStack = ($callStack[1..0]).Command -join ' => '

    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Processing ($primary_server ~ $dr_server)$(if($Debug){" in DEBUG mode"}).." | Tee-Object $LogFile -Append | Write-Output

    $filename = "HadrSync__"+$($Script.Replace('.ps1',''))+"__"+$primary_server.Replace('/', '_') + "__ScriptOut__$Dtmm.sql"
    $outfile = Join-Path -Path $OutputPath -ChildPath $filename
    
    # Checking existence of the table in PROD & DR
    $sqlcheckTable = "select count(1) as is_present from DBA.sys.tables where name='auto_stats_config' and schema_id=schema_id('dbo');"
    $checkTableProd = ExecuteQuery -SqlInstance $primary_server -Query $sqlcheckTable -Database "DBA";
    $checkTableDR = ExecuteQuery -SqlInstance $dr_server -Query $sqlcheckTable -Database "DBA";
    
    if ($checkTableProd.is_present -eq 0 -or $checkTableDR.is_present -eq 0) {
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => table DBA.dbo.auto_stats_conf not present on $primary_server or $dr_server." | Tee-Object $LogFile -Append | Write-Output
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => No action taken." | Tee-Object $LogFile -Append | Write-Output
        return;
    }

    # Sync table data
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Sync data of DBA.dbo.auto_stats_conf using BulkCopy.." | Tee-Object $LogFile -Append | Write-Output
    If ($WhatIf) 
    {
        #"{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Running below command.." | Tee-Object $LogFile -Append | Write-Output
        @"
Sync-Table -source_server '$primary_server' -source_db 'DBA' ``
            -source_schema 'dbo' -source_table 'auto_stats_config' ``
            -destination_server '$dr_server' -destination_db 'DBA' ``
            -destination_schema 'dbo' -destination_table 'auto_stats_config' ``
            -truncate_destination
"@  | Tee-Object $outfile -Append | Out-Null
    }
    else {
        Sync-Table -source_server $primary_server -source_db "DBA" `
                    -source_schema "dbo" -source_table "auto_stats_config" `
                    -destination_server $dr_server -destination_db "DBA" `
                    -destination_schema "dbo" -destination_table "auto_stats_config" `
                    -truncate_destination
    }
    
    if($WhatIf) {
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Script Output in below file..`n'$outfile'" | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
    }
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(FINISH)", "$cmdCallStack => Completed on ($primary_server ~ $dr_server)." | Tee-Object $LogFile -Append | Write-Output
}

