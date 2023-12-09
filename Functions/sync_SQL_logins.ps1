function sync_SQL_logins
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
        $Script = 'sync_SQL_logins.ps1'
    }
    $callStack = Get-PSCallStack
    #$cmdCallStack = ($callStack[($callStack.Count-2)..0]).Command -join ' => '
    $cmdCallStack = ($callStack[1..0]).Command -join ' => '

    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Processing ($primary_server ~ $dr_server)$(if($Debug){" in DEBUG mode"}).." | Tee-Object $LogFile -Append | Write-Output

    #Write-Debug "Inside $Script"
    #$filename = $primary_server.Replace('/', '_') + '_' + (Get-Date -Format 'yyyyMMddHHmm') + '_Script.sql'
    $filename = "HadrSync__"+$($Script.Replace('.ps1',''))+"__"+$primary_server.Replace('/', '_') + "__ScriptOut__$Dtmm.sql"
    $outfile = Join-Path -Path $OutputPath -ChildPath $filename
    
    #getting SQL logins list
    $tsqlSysLogins = @"
SELECT loginname as name 
FROM master..syslogins  l
JOIN sys.server_principals p ON l.sid=p.sid
WHERE l.isntuser  = 0
AND l.isntgroup = 0
AND is_disabled = 0
AND loginname   !='sa'
AND loginname not like '%#%'
AND loginname   !='dbmon'
AND loginname   != 'igniteP'
AND loginname   != 'sqlmon'
AND loginname   != 'distributor_admin'
AND loginname   != 'dbinternal' -- DBA#62656#3
AND loginname not like '%_sa'
AND p.type_desc != 'ASYMMETRIC_KEY_MAPPED_LOGIN'
"@

    $resultSysLogins = @()
    $primary_logins = ''
    $resultSysLogins += Invoke-Sqlcmd -ServerInstance $primary_server -Query $tsqlSysLogins -QueryTimeout 120;
    if($resultSysLogins.Count -gt 0) {
        $primary_logins = [string]::join("','", $resultSysLogins.name);
    }
       

    # get a list of logins to be exculed (We are dropping and re-creating the logins ensure passwords stay intact.
    # However dropping a login will delete linked server login definitions. Since we cannot sync linked server
    # login configurations automatically, these logins should be excluded
    $tsqlLinkedServerLogins = @"
SELECT name
FROM sys.linked_logins ll
JOIN sys.server_principals p on ll.local_principal_id = p.principal_id
WHERE local_principal_id !=0
"@
    #Trap { "Error:: Server: $dr_server Query: $sql2 Error: $_.Exception.Message"; Continue } 
    #$logins_exclusion_list_hash = (mExecuteQuery -SqlInstance $dr_server -Query $sql2).Tables[0]
    $resultLinkedServerLogins = @()
    $resultLinkedServerLogins += Invoke-Sqlcmd -ServerInstance $primary_server -Query $tsqlLinkedServerLogins -QueryTimeout 120;

    $logins_exclusion_list = ''
    if($resultLinkedServerLogins.Count -gt 0) {
        $logins_exclusion_list = [string]::join("','", $resultLinkedServerLogins.name)
    }

    $tsqlFetchProdLoginDetails = @"
SELECT '
IF EXISTS (SELECT * FROM syslogins WHERE name = '''+name+''') AND NOT EXISTS (SELECT 1 FROM sys.dm_exec_sessions WHERE login_name = '''+name+''')  
BEGIN;ALTER LOGIN [' + name + '] WITH PASSWORD =',CONVERT(varbinary(256),sl.password_hash),+' HASHED ,CHECK_EXPIRATION = OFF, CHECK_POLICY =OFF;ALTER LOGIN [' + name + '] WITH  CHECK_POLICY =ON;END;',
'IF NOT EXISTS (SELECT 1 FROM syslogins WHERE name = '''+name+''') 
CREATE LOGIN [' + name + '] WITH PASSWORD =',CONVERT(varbinary(256),sl.password_hash),+'HASHED, sid =',sid,',CHECK_EXPIRATION = OFF, CHECK_POLICY =ON'
        ,name
FROM master..syslogins l
outer apply ( select sl.password_hash from master.sys.sql_logins sl where sl.name = l.name) as sl
WHERE loginname IN ('$primary_logins')
AND loginname not in ('$logins_exclusion_list')
"@

    $results_hash = (ExecuteQuery -SqlInstance $primary_server -Query $tsqlFetchProdLoginDetails)

    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => ALTER/CREATE LOGIN on $dr_server.." | Tee-Object $LogFile -Append | Write-Output
    foreach ($login in $results_hash) {
        $loginName = $login.name
        $tsqlAlterLogin = $login.Column1 + $(ConvertTo-SQLHashString ($login.Column2)) + $login.Column3
        $tsqlCreateLogin = $login.Column4 + $(ConvertTo-SQLHashString ($login.Column5)) + $login.Column6 + $(ConvertTo-SQLHashString ($login.sid)) + $login.Column7
			
        #"{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Executing ALTER/CREATE LOGIN [$loginName].. on $dr_server.." | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
        If ($WhatIf) {
            "$tsqlAlterLogin" | Tee-Object $outfile -Append | Out-Null
            "$tsqlCreateLogin" | Tee-Object $outfile -Append | Out-Null
        }
        else {
            ExecuteNonQuery -SqlInstance $dr_server -Query $tsqlAlterLogin
            ExecuteNonQuery -SqlInstance $dr_server -Query $tsqlCreateLogin
        }
    }

    # Get Host Names
    $sql = "SELECT SERVERPROPERTY('ComputerNamePhysicalNetBIOS') AS HostName;";
    $primary_host = (ExecuteQuery -SqlInstance $primary_server -Query $sql).HostName;
    $dr_host = (ExecuteQuery -SqlInstance $dr_server -Query $sql).HostName;
     
    # Sync Windows logins
    #$sql = "SELECT loginname from master.sys.syslogins where (isntuser=1 or isntgroup=1) and loginname not like 'NT %' "
    $sql = "SELECT REPLACE(loginname, '${primary_host}', '${dr_host}') AS loginname from master.sys.syslogins where (isntuser=1 or isntgroup=1) and loginname not like 'NT %' "
    $primary_win_logins = ExecuteQuery -SqlInstance $primary_server -Query $sql
    $dr_win_logins = ExecuteQuery -SqlInstance $dr_server -Query $sql
     
    # get the list of logins missing on dr
    $missing_win_logins = @()
    $missing_win_logins += $primary_win_logins | where-object { $_.loginname -cnotin $dr_win_logins.loginname} | Select-Object -ExpandProperty loginname

    # create the missing logins
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Create Windows Logins on $dr_server.." | Tee-Object $LogFile -Append | Write-Output
    foreach ($login in $missing_win_logins) {
        $tsqlCreateWinLogin = "CREATE LOGIN [$($login)] FROM WINDOWS;"
        
        #"{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Executing CREATE LOGIN [$login].. on $dr_server.." | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
        If ($WhatIf) {
            "$tsqlCreateWinLogin" | Tee-Object $outfile -Append | Out-Null
        }
        else {
            ExecuteNonQuery -SqlInstance $dr_server -Query $tsqlCreateWinLogin
        }
    }

    # Sync disbled/enabled login properties
    # disable all logins which are in an disabled state
    $tsqlDisabledLogins = @"
SELECT name FROM sys.server_principals 
WHERE is_disabled = 1
AND name != 'sa' AND name not like '%#'
AND name != 'PLSystemVB' and name != 'DBABSNYC1\\urseag-admin' AND name not like 'DBEXT%'
AND type_desc IN ('WINDOWS_LOGIN','SQL_LOGIN')
"@
    $disabled_logins = @() 
    $disabled_logins += (ExecuteQuery -SqlInstance $primary_server -Query $tsqlDisabledLogins | Select-Object -ExpandProperty name)
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Sync Logins state (DISABLED) on $dr_server.." | Tee-Object $LogFile -Append | Write-Output
    if ($disabled_logins.Count -gt 0) {
        foreach ($login in $disabled_logins) {
            $tsqlDisableLogin = "IF EXISTS (SELECT 1 FROM sys.syslogins WHERE name= '$login') ALTER LOGIN [$login] DISABLE;"
            
            #"{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Executing DISABLE LOGIN [$login] on $dr_server.." | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
            If ($WhatIf) {
                "$tsqlDisableLogin" | Tee-Object $outfile -Append | Out-Null
            }
            else {
                ExecuteNonQuery -SqlInstance $dr_server -Query $tsqlDisableLogin
            }
        }
    }
     
    # enable all logins which are in an enabled state
    $tsqlEnabledLogins = @"
SELECT name FROM sys.server_principals 
WHERE is_disabled = 0
AND name != 'sa' AND name not like '%#'
AND name != 'PLSystemVB' AND name != 'DBABSNYC1\\urseag-admin' AND name not like 'DBEXT%' AND name not like 'NT SERVICE\%'
AND type_desc IN ('WINDOWS_LOGIN','SQL_LOGIN')
"@

    $enabled_logins = @()
    $enabled_logins += (ExecuteQuery -SqlInstance $primary_server -Query $tsqlEnabledLogins | Select-Object -ExpandProperty name)
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Sync Logins state (ENABLED) on $dr_server.." | Tee-Object $LogFile -Append | Write-Output
    if ($enabled_logins.Count -gt 0) {
        foreach ($login in $enabled_logins) {
            $tsqlEnableLogin = "IF EXISTS (SELECT 1 FROM sys.syslogins WHERE name= '$login') ALTER LOGIN [$login]  ENABLE;"
            
            #"{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Executing ENABLE LOGIN [$login] on $dr_server.." | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
            If ($WhatIf) {
                "$tsqlEnableLogin" | Tee-Object $outfile -Append | Out-Null
            }
            else {
                ExecuteNonQuery -SqlInstance $dr_server -Query $tsqlEnableLogin
            }
        }
    }

    # Sync assymetric key logins   # Ref : DBA#26600, DBA#26355
    $tsqlAsymetricKeyLogins = @"
SELECT loginname
FROM master..syslogins  l
INNER JOIN sys.server_principals p ON l.sid=p.sid
WHERE l.isntuser  = 0
AND l.isntgroup = 0
AND is_disabled = 0
AND loginname  != 'sa'
AND loginname not like '%#%'
AND loginname !='dbmon'
AND loginname != 'igniteP'
AND loginname != 'distributor_admin'
AND p.type_desc = 'ASYMMETRIC_KEY_MAPPED_LOGIN'
"@
    $primary_ak_logins = @()
    $primary_ak_logins += (ExecuteQuery -SqlInstance $primary_server -Query $tsqlAsymetricKeyLogins | Select-Object -ExpandProperty loginname)
    $dr_ak_logins = @()
    $dr_ak_logins += (ExecuteQuery -SqlInstance $dr_server -Query $tsqlAsymetricKeyLogins | Select-Object -ExpandProperty loginname)

                    
    # get the list of logins missing on dr
    $create_ak_logins = @()
    $create_ak_logins += $primary_ak_logins | where-object { $_ -cnotin $dr_ak_logins }
    $delete_ak_logins = @()
    $delete_ak_logins += $dr_ak_logins | where-object { $_ -cnotin $primary_ak_logins }

    # create the missing logins
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Create asymmetric key logins on $dr_server.." | Tee-Object $LogFile -Append | Write-Output
    foreach ($login in $create_ak_logins)
    {
        $sqlCreateAsymetricLogin = @"
SELECT  'CREATE LOGIN ' + ssp.loginname + ' FROM ASYMMETRIC KEY ' + sak.name
FROM master..syslogins ssp
INNER JOIN sys.asymmetric_keys sak ON ssp.sid = sak.sid
WHERE ssp.loginname = '$login' 
"@

        #"{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Executing CREATE LOGIN [$login] on $dr_server.." | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
        If ($WhatIf) {
            "$sqlCreateAsymetricLogin" | Tee-Object $outfile -Append | Out-Null
        }
        else {
            ExecuteNonQuery -SqlInstance $dr_server -Query $sqlCreateAsymetricLogin
        }
    }

    # Drop stale asymmetric key logins
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Drop stale asymmetric key logins on $dr_server.." | Tee-Object $LogFile -Append | Write-Output
    foreach ($login in $delete_ak_logins)
    {
        $sqlDropAsymetricLogin = "IF NOT EXISTS (SELECT 1 FROM sys.dm_exec_sessions WHERE login_name = '$login') drop login [$login] "
                                                
        #"{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Executing DROP LOGIN [$login] on $dr_server.." | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
        If ($WhatIf) {
            "$sqlDropAsymetricLogin" | Tee-Object $outfile -Append | Out-Null
        }
        else {
            ExecuteNonQuery -SqlInstance $dr_server -Query $sqlDropAsymetricLogin
        }
    }
   
     
    #Sync dropped logins
    $tsqlLogins = @"
SELECT loginname from sys.syslogins 
where loginname not like '%#' and loginname not like 'NT%' 
and loginname not in ('dbmon','igniteP','distributor_admin','sa')
"@
    $primary_logins = @()
    $primary_logins += (ExecuteQuery -SqlInstance $primary_server -Query $tsqlLogins | Select-Object -ExpandProperty loginname)
    $dr_logins = @()
    $dr_logins += (ExecuteQuery -SqlInstance $dr_server -Query $tsqlLogins | Select-Object -ExpandProperty loginname)
    $dr_drop_logins = @()
    $dr_drop_logins += $dr_logins | where-object {$_ -cnotin $primary_logins}

    # Drop stale logins
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Drop stale logins on $dr_server.." | Tee-Object $LogFile -Append | Write-Output
    foreach ($login in $dr_drop_logins) {
        $sqlDropStaleLogin = "IF NOT EXISTS (SELECT 1 FROM sys.dm_exec_sessions WHERE login_name = '$login') drop login [$login] "
        
        #"{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Executing DROP LOGIN [$login] on $dr_server.." | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
        If ($WhatIf) {
            "$sqlDropStaleLogin" | Tee-Object $outfile -Append | Out-Null
        }
        else {
            ExecuteNonQuery -SqlInstance $dr_server -Query $sqlDropStaleLogin
        }
    }

    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => TSQL Output scripted out in below file..`n'$outfile'" | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(FINISH)", "$cmdCallStack => Completed on ($primary_server ~ $dr_server)." | Tee-Object $LogFile -Append | Write-Output
}
