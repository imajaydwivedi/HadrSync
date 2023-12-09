function set_simple_recovery_for_non_mirrored_databases
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
        $Script = 'set_simple_recovery_for_non_mirrored_databases.ps1'
    }
    $callStack = Get-PSCallStack
    $cmdCallStack = ($callStack[1..0]).Command -join ' => '

    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Processing ($primary_server ~ $dr_server)$(if($Debug){" in DEBUG mode"}).." | Tee-Object $LogFile -Append | Write-Output

    $filename = "HadrSync__"+$($Script.Replace('.ps1',''))+"__"+$primary_server.Replace('/', '_') + "__ScriptOut__$Dtmm.sql"
    $outfile = Join-Path -Path $OutputPath -ChildPath $filename
    
    #Write-Debug "Inside sync_SQL_server_configuration"
    #return

    # Get Non-Simple Recovery dbs
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => find full recovery dbs on $dr_server.." | Tee-Object $LogFile -Append | Write-Output
    $sql = @"
SELECT name --, DATABASEPROPERTYEX(name,'Updateability')
FROM sys.databases
WHERE state_desc = 'ONLINE'
AND source_database_id IS NULL
AND recovery_model_desc != 'SIMPLE'
AND DATABASEPROPERTYEX(name,'Updateability') = 'READ_WRITE'
"@
    $dbs = @()
    $dbs += ExecuteQuery -SqlInstance $dr_server -Query $sql

    if ($dbs.Count -gt 0)
    {
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => $($dbs.Count) db(s) found with full recovery model on $dr_server." | Tee-Object $LogFile -Append | Write-Output
        foreach ($db in $dbs)
        {
            $alter = "ALTER DATABASE [$($db.name)] SET RECOVERY SIMPLE;";
            if ($OutputPath) {
                $alter + "`rGO `r " | Out-File -Append -filepath $outfile -ErrorAction stop
            }

            if (-not $WhatIf) {
                ExecuteNonQuery -SqlInstance $dr_server -Query $alter -Database 'master';
            }
        }
    }
    else {
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => No db found with full recovery model on $dr_server." | Tee-Object $LogFile -Append | Write-Output
    }
                      
    if ($WhatIf) {
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Tsql scripted out in below file..`n'$outfile'" | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
    }
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(FINISH)", "$cmdCallStack => Completed on ($primary_server ~ $dr_server)." | Tee-Object $LogFile -Append | Write-Output
}
