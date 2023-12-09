function sync_SQL_database_permissions
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [string]$primary_server,
        [Parameter(Mandatory = $true)]
        [string]$dr_server,
        [Parameter(Mandatory = $true)]
        [string]$database,
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
        $Script = 'sync_SQL_database_permissions.ps1'
    }
    $callStack = Get-PSCallStack
    $cmdCallStack = ($callStack[1..0]).Command -join ' => '

    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Processing ($primary_server ~ $dr_server) for [$database]$(if($Debug){" in DEBUG mode"}).." | Tee-Object $LogFile -Append | Write-Output
    
    $filename = "HadrSync__"+$($Script.Replace('.ps1',''))+"__"+$primary_server.Replace('/', '_') + "__" + $database + "__ScriptOut__$Dtmm.sql"
    $outfile = Join-Path -Path $OutputPath -ChildPath $filename

    #Write-Debug "Inside sync_SQL_database_permissions"

    # checking the existence of database
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Check for $database existence.." | Tee-Object $LogFile -Append | Write-Output
    $sql = "select count(1) as is_present from master.sys.databases where name = '$database' and state_desc='ONLINE'"
    $primary_db_exists_token = (ExecuteQuery -SqlInstance $primary_server -Query $sql).is_present
    $dr_db_exists_token = (ExecuteQuery -SqlInstance $dr_server -Query $sql).is_present

    if ($primary_db_exists_token -eq 0 -or $dr_db_exists_token -eq 0) {
        Write-Output "$database does not exist on $primary_server or $dr_server";
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => [$database] not found on [$primary_server] or [$dr_server]." | Tee-Object $LogFile -Append | Write-Output
        return
    }

    #sync sql users
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Sync SQL Users.." | Tee-Object $LogFile -Append | Write-Output
    $sql = @"
SELECT 'IF NOT EXISTS (SELECT * FROM sys.database_principals AS dp WHERE dp.name = '''+dp.name+''') '+CHAR(10)+
			'CREATE USER ['+dp.name+'] '+ (CASE WHEN sp.name IS NOT NULL THEN 'FOR LOGIN ['+sp.name+']' ELSE 'WITHOUT LOGIN' END)+
			' WITH DEFAULT_SCHEMA=['+ISNULL(dp.default_schema_name,'dbo')+'];' AS [create_user_sql]
		,dp.name
FROM sys.database_principals AS dp
LEFT JOIN sys.server_principals sp ON dp.sid = sp.sid
WHERE (dp.type in ('S'))
        AND dp.name NOT LIKE '##%##'
        AND dp.name NOT LIKE 'NT AUTHORITY%'
        AND dp.name NOT LIKE 'NT SERVICE%'
        AND dp.name <> ('sa')
        AND dp.default_schema_name IS NOT NULL
        AND dp.name <> 'distributor_admin'
        AND dp.principal_id > 4;
"@
    $db_sql_users = @()
    $db_sql_users += ExecuteQuery -SqlInstance $primary_server -Query $sql -db $database

    if ($db_sql_users.Count -gt 0)
    {
        foreach ($user in $db_sql_users)
        {
            $createUser =  $user.create_user_sql
            If ($WhatIf) {
                "$('use ['+$database+']; '+$createUser)" | Tee-Object $outfile -Append | Out-Null
            }
            else {
                ExecuteNonQuery -SqlInstance $dr_server -Query $createUser -db $database;
            }
        }

        if ($WhatIf) {
            "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Missing db sql user(s) scripted out in below file..`n'$outfile'" | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
        }
    }
               
    #sync windows users
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Sync windows users.." | Tee-Object $LogFile -Append | Write-Output
    $sql = @"
SELECT 'IF NOT EXISTS (SELECT * FROM sys.database_principals AS dp WHERE dp.name = '''+dp.name+''') '+CHAR(10)+
			'CREATE USER ['+dp.name+'] '+ (CASE WHEN sp.name IS NOT NULL THEN 'FOR LOGIN ['+sp.name+']' ELSE 'WITHOUT LOGIN' END)+
			' WITH DEFAULT_SCHEMA=['+ISNULL(dp.default_schema_name,'dbo')+'];' AS [create_user_sql]
		,dp.name
FROM sys.database_principals AS dp
LEFT JOIN sys.server_principals sp ON dp.sid = sp.sid
WHERE (dp.type in ('G','U'))
        AND dp.name NOT LIKE '##%##'
        AND dp.name NOT LIKE 'NT AUTHORITY%'
        AND dp.name NOT LIKE 'NT SERVICE%'
        AND dp.name <> ('sa')
        AND dp.default_schema_name IS NOT NULL
        AND dp.name <> 'distributor_admin'
        AND dp.principal_id > 4;
"@
    $db_win_users = @()
    $db_win_users += ExecuteQuery -SqlInstance $primary_server -Query $sql -db $database
    if ($db_win_users.count -gt 0)
    {
        foreach ($user in $db_win_users)
        {
            $createUser =  $user.create_user_sql
            If ($WhatIf) {
                "$('use ['+$database+']; '+$createUser)" | Tee-Object $outfile -Append | Out-Null
            }
            else {
                ExecuteNonQuery -SqlInstance $dr_server -Query $createUser -db $database;
            }
        }

        if ($WhatIf) {
            "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Missing windows db user(s) scripted out in below file..`n'$outfile'" | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
        }
    }

    #sync roles
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Sync db roles.." | Tee-Object $LogFile -Append | Write-Output
    $sql = "SELECT [create_role] = 'IF NOT EXISTS (SELECT 1 FROM [$database].sys.database_principals WHERE name='''+name+''')  CREATE ROLE [' + name + '];'  FROM [$database].sys.database_principals WHERE type='R' AND is_fixed_role=0 AND principal_id>0";
    $db_roles = @()
    $db_roles += ExecuteQuery -SqlInstance $primary_server -Query $sql -db $database
    if ($db_roles.count -gt 0)
    {
        foreach ($role in $db_roles)
        {
            $createRole =  $role.create_role
            If ($WhatIf) {
                "$('use ['+$database+']; '+$createRole)" | Tee-Object $outfile -Append | Out-Null
            }
            else {
                ExecuteNonQuery -SqlInstance $dr_server -Query $createRole -db $database;
            }
        }

        if ($WhatIf) {
            "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Missing db role(s) scripted out in below file..`n'$outfile'" | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
        }
    }

    # Sync schema authorization
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Find schemas for [$database] database on ($primary_server ~ $dr_server).." | Tee-Object $LogFile -Append | Write-Output
    $tsqlSchemas = @"
select s.name as sch_name, p.name as own_name
from sys.schemas s 
join sys.database_principals p 
on p.principal_id = s.principal_id
where schema_id<16384;
"@
    $prod_schemas = @()
    $prod_schemas += ExecuteQuery -SqlInstance $primary_server -Query $tsqlSchemas -db $database;
    $dr_schemas = @()
    $dr_schemas += ExecuteQuery -SqlInstance $dr_server -Query $tsqlSchemas -db $database;

    # Get changed schemas list
    $changed_schemas = @()
    $changed_schemas += (Compare-Object -CaseSensitive -ReferenceObject $prod_schemas -DifferenceObject $dr_schemas -Property sch_name, own_name | where-object { $_.SideIndicator -eq "<=" })
    
    if ($changed_schemas.Count -gt 0)
    {
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => $($changed_schemas.Count) changed schema(s) found." | Tee-Object $LogFile -Append | Write-Output
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Scriptout changed schema(s)$(if(-not $WhatIf){' and create on DR'}).." | Tee-Object $LogFile -Append | Write-Output
        
        foreach ($sch in $changed_schemas)
        {
            $sch_def = @"
IF SCHEMA_ID('$($sch.sch_name)') IS NULL
    EXEC ('create schema [$($sch.sch_name)]')
ALTER AUTHORIZATION ON SCHEMA::[$($sch.sch_name)] TO [$($sch.own_name)];
"@
            if ($OutputPath) { "use [$database]; " + $sch_def + "`rGO `r " | Out-File -Append -filepath $outfile  -ErrorAction stop }

            if (-not $WhatIf) {
                ExecuteNonQuery -SqlInstance $dr_server -Query $sch_def -db $database;
            }
        }

        if ($WhatIf) {
            "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Changed schema(s) scripted out in below file..`n'$outfile'" | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
        }
    }
     
    #sync role members
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Sync db role members.." | Tee-Object $LogFile -Append | Write-Output
    $sql = "SELECT [add_role_member] = 'ALTER ROLE ' + QUOTENAME(USER_NAME(rm.role_principal_id), '') + '  ADD MEMBER '+QUOTENAME(USER_NAME(rm.member_principal_id), '')  +';'
FROM [$database].sys.database_role_members AS rm
WHERE USER_NAME(rm.member_principal_id) NOT IN ('dbo','sys')
ORDER BY rm.role_principal_id ASC";
    $db_role_members = @()
    $db_role_members += ExecuteQuery -SqlInstance $primary_server -Query $sql -db $database
    if ($db_role_members.Count -gt 0)
    {
        foreach ($member in $db_role_members)
        {
            $addRoleMember =  $member.add_role_member
            If ($WhatIf) {
                "$('use ['+$database+']; '+$addRoleMember)" | Tee-Object $outfile -Append | Out-Null
            }
            else {
                ExecuteNonQuery -SqlInstance $dr_server -Query $addRoleMember -db $database;
            }
        }

        if ($WhatIf) {
            "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Missing db role members scripted out in below file..`n'$outfile'" | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
        }
    }

    #sync database permissions
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => sync database permissions.." | Tee-Object $LogFile -Append | Write-Output
    $sql = "SELECT [sql_perm] = 
CASE WHEN perm.state <> 'W' THEN perm.state_desc ELSE 'GRANT' END +
SPACE(1) + perm.permission_name + SPACE(1) + SPACE(1) + 'TO' + SPACE(1) +
QUOTENAME(usr.name) COLLATE database_default +
CASE WHEN perm.state <> 'W' THEN SPACE(0) ELSE SPACE(1) + 'WITH GRANT OPTION' END
+';'
-- + NCHAR(10)
FROM [$database].sys.database_permissions AS perm
JOIN [$database].sys.database_principals AS usr
ON perm.grantee_principal_id = usr.principal_id
AND perm.major_id = 0
WHERE usr.name NOT IN ('dbo','sys')
ORDER BY perm.permission_name ASC, perm.state_desc ASC";
    $db_db_perms = @()
    $db_db_perms += ExecuteQuery -SqlInstance $primary_server -Query $sql -db $database
    if ($db_db_perms.Count -gt 0)
    {
        foreach ($perms in $db_db_perms)
        {
            $sqlPerm =  $perms.sql_perm
            If ($WhatIf) {
                "$('use ['+$database+']; '+$sqlPerm)" | Tee-Object $outfile -Append | Out-Null
            }
            else {
                ExecuteNonQuery -SqlInstance $dr_server -Query $sqlPerm -db $database;
            }
        }

        if ($WhatIf) {
            "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Missing db permissions scripted out in below file..`n'$outfile'" | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
        }
    }

    # sync schema permissions
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => sync schema permissions.." | Tee-Object $LogFile -Append | Write-Output
    $sql = @"
SELECT [sql_perm] = 'IF SCHEMA_ID('''+SCHEMA_NAME(perm.major_id)+''') IS NOT NULL '+
				state_desc+' '+permission_name+' ON '+class_desc+'::'+SCHEMA_NAME(major_id)+' TO '+QUOTENAME(USER_NAME(grantee_principal_id)) +';' 
FROM sys.database_permissions perm where class_desc = 'SCHEMA';
"@
    $db_schema_perms = @()
    $db_schema_perms += ExecuteQuery -SqlInstance $primary_server -Query $sql -db $database
    if ($db_schema_perms.Count -gt 0)
    {
        foreach ($schema in $db_schema_perms)
        {
            $sqlPerm = $schema.sql_perm
            If ($WhatIf) {
                "$('use ['+$database+']; '+$sqlPerm)" | Tee-Object $outfile -Append | Out-Null
            }
            else {
                ExecuteNonQuery -SqlInstance $dr_server -Query $sqlPerm -db $database;
            }
        }

        if ($WhatIf) {
            "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Missing schema permissions scripted out in below file..`n'$outfile'" | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
        }
    }

    #sync DB Object Permissions
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Sync Object level permissions for [$database].." | Tee-Object $LogFile -Append | Write-Output
    $sqlObjectPermissions = @"
SELECT [obj_perm] =  'IF '+(CASE WHEN class_desc = 'SCHEMA' 
											then 'SCHEMA_ID('''+schema_name(perm.major_id)+''') IS NOT NULL ' 
											else 'OBJECT_ID('''+quotename(schema_name(obj.schema_id)) +'.'+ quotename(obj.name)+''') IS NOT NULL  '
											end) +
				CASE WHEN perm.state <> 'W' THEN perm.state_desc ELSE 'GRANT' END + SPACE(1) + 
				perm.permission_name + SPACE(1) + 'ON ' + 
				(case when class_desc = 'SCHEMA' then ' SCHEMA::'+quotename(schema_name(perm.major_id)) else quotename(schema_name(obj.schema_id))+'.'+quotename(obj.name) end) + 
				(CASE WHEN cl.column_id IS NULL THEN SPACE(0) ELSE '(' + QUOTENAME(cl.name) + ')' END) + SPACE(1) + 'TO' + SPACE(1) + 
				QUOTENAME(usr.name) COLLATE database_default + CASE  WHEN perm.state <> 'W' THEN SPACE(0) ELSE SPACE(1) + 'WITH GRANT OPTION' END + NCHAR(10)
FROM sys.database_permissions AS perm
INNER JOIN sys.objects AS obj ON perm.major_id = obj.[object_id]
INNER JOIN sys.database_principals AS usr ON perm.grantee_principal_id = usr.principal_id
LEFT JOIN sys.columns AS cl ON cl.column_id = perm.minor_id
	AND cl.[object_id] = perm.major_id
WHERE usr.name NOT IN ('dbo','sys')
	AND class_desc = 'OBJECT_OR_COLUMN'
ORDER BY perm.major_id, perm.permission_name ASC, perm.state_desc ASC;
"@
    $DB_Objectperms = @()
    $DB_Objectperms += ExecuteQuery -SqlInstance $primary_server -Query $sqlObjectPermissions -db $database
    if ($DB_Objectperms.Count -gt 0)
    {
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => $($DB_Objectperms.Count) Object level permissions found.." | Tee-Object $LogFile -Append | Write-Output
        foreach ($Objectperms in $DB_Objectperms)
        {
            $perms = $Objectperms.obj_perm
            If ($WhatIf) {
                "$('use ['+$database+']; '+$perms)" | Tee-Object $outfile -Append | Out-Null
            }
            else {
                ExecuteNonQuery -SqlInstance $dr_server -Query $perms -db $database;
            }
        }

        if ($WhatIf) {
            "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Object permissions scripted out in below file..`n'$outfile'" | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
        }
    }
    else {
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => No Object permissions found." | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
    }


    #sync drop stale users
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => sync drop stale users.." | Tee-Object $LogFile -Append | Write-Output
    $sql = "SELECT name from sys.sysusers";
    $primary_users = @()
    $primary_users += ExecuteQuery -SqlInstance $primary_server -Query $sql -db $database;
    $dr_users = @()
    $dr_users += ExecuteQuery -SqlInstance $dr_server -Query $sql -db $database;
    $dr_only_users = @()
    $dr_only_users += $dr_users.name | where-Object { if ($_ -cnotin $primary_users.name) { $_ } }

    if ($dr_only_users.Count -gt 0)
    {
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => $($dr_only_users.Count) stale users found on DR.." | Tee-Object $LogFile -Append | Write-Output
        foreach ($user in $dr_only_users)
        {
            $sql = "drop user [$user];"
            If ($WhatIf) {
                "$('use ['+$database+']; '+$sql)" | Tee-Object $outfile -Append | Out-Null
            }
            else {
                ExecuteNonQuery -SqlInstance $dr_server -Query $sql -db $database;
            }
        }

        if ($WhatIf) {
            "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Drop stale users scripted out in below file..`n'$outfile'" | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
        }
    }
    
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => TSQL Output scripted out in below file..`n'$outfile'" | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(FINISH)", "$cmdCallStack => Completed on ($primary_server ~ $dr_server) for [$database]." | Tee-Object $LogFile -Append | Write-Output
}
