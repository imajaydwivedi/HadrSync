function sync_database_objects
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
        $Script = 'sync_database_objects.ps1'
    }
    $callStack = Get-PSCallStack
    $cmdCallStack = ($callStack[1..0]).Command -join ' => '

    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Processing ($primary_server ~ $dr_server) for [$database]$(if($Debug){" in DEBUG mode"}).." | Tee-Object $LogFile -Append | Write-Output
    
    $filename = "HadrSync__"+$($Script.Replace('.ps1',''))+"__"+$primary_server.Replace('/', '_') + "__" + $database + "__ScriptOut__$Dtmm.sql"
    $outfile = Join-Path -Path $OutputPath -ChildPath $filename

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

    [System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO') | out-null
    $smoprod = New-Object ('Microsoft.SqlServer.Management.Smo.Server') $primary_server
    $smodr = New-Object ('Microsoft.SqlServer.Management.Smo.Server') $dr_server
    
    # 01 - Sync schema names in database so that script won't fail while creating missing functions,procs 
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Create schemas for [$database] database on $dr_server.." | Tee-Object $LogFile -Append | Write-Output
    $tsqlSchemas = @"
select s.name as sch_name, p.name as own_name
from sys.schemas s 
join sys.database_principals p 
on p.principal_id = s.principal_id
where schema_id<16384;
"@
    $prod_schemas = @()
    $prod_schemas += ExecuteQuery -SqlInstance $primary_server -Query $tsqlSchemas -Database $database;
    $dr_schemas = @()
    $dr_schemas += ExecuteQuery -SqlInstance $dr_server -Query $tsqlSchemas -Database $database;

    # Get missing schemas list in DR
    $missing_schemas = @()
    $missing_schemas += (Compare-Object -CaseSensitive -ReferenceObject $prod_schemas -DifferenceObject $dr_schemas -Property sch_name | where-object { $_.SideIndicator -eq "<=" }) | Select-Object -ExpandProperty sch_name;
    
    if ($missing_schemas.Count -gt 0)
    {
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => $($missing_schemas.Count) missing schema(s) found." | Tee-Object $LogFile -Append | Write-Output
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Scriptout missing schema(s)$(if(-not $WhatIf){' and create on DR'}).." | Tee-Object $LogFile -Append | Write-Output
        
        $prod_schemas_filtered = @()
        $prod_schemas_filtered = $prod_schemas | Where-Object {$_.sch_name -cin $missing_schemas}
        foreach ($sch in $prod_schemas_filtered)
        {
            $sch_def = "create schema [$($sch.sch_name)] AUTHORIZATION [$($sch.own_name)]"
            if ($OutputPath) { "use [$database]; " + $sch_def + "`rGO `r " | Out-File -Append -filepath $outfile  -ErrorAction stop }

            if (-not $WhatIf) {
                ExecuteNonQuery -SqlInstance $dr_server -Query $sch_def -Database $database;
            }
        }

        if ($WhatIf) {
            "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Missing schema(s) scripted out in below file..`n'$outfile'" | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
        }
    }

    # 02 - Sync database users
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Create missing users for [$database] database on $dr_server.." | Tee-Object $LogFile -Append | Write-Output
    $tsqlUsers = @"
SELECT dp.name, 
		'IF NOT EXISTS (SELECT * FROM sys.database_principals AS dp WHERE dp.name = '''+dp.name+''') '+CHAR(10)+
			'CREATE USER ['+dp.name+'] '+ (CASE WHEN sp.name IS NOT NULL THEN 'FOR LOGIN ['+sp.name+']' ELSE 'WITHOUT LOGIN' END)+
			' WITH DEFAULT_SCHEMA=['+ISNULL(dp.default_schema_name,'dbo')+'];' AS [tsql_add]
FROM sys.database_principals AS dp
LEFT JOIN sys.server_principals sp ON dp.sid = sp.sid
WHERE (dp.type in ('S','G','U'))
        AND dp.name NOT LIKE '##%##'
        AND dp.name NOT LIKE 'NT AUTHORITY%'
        AND dp.name NOT LIKE 'NT SERVICE%'
        AND dp.name <> ('sa')
        AND dp.default_schema_name IS NOT NULL
        AND dp.name <> 'distributor_admin'
        AND dp.principal_id > 4;
"@
    $prod_users = @()
    $prod_users += ExecuteQuery -SqlInstance $primary_server -Query $tsqlUsers -Database $database;
    $dr_users = @()
    $dr_users += ExecuteQuery -SqlInstance $dr_server -Query $tsqlUsers -Database $database;

    #Get missing users list in DR
    $missing_users = @()
    $missing_users += (Compare-Object -CaseSensitive -ReferenceObject $prod_users -DifferenceObject $dr_users -Property name | where-object { $_.SideIndicator -eq "<=" }) | Select-Object -ExpandProperty name -Unique
    
    if ($missing_users.Count -gt 0)
    {
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => $($missing_users.Count) missing user(s) found." | Tee-Object $LogFile -Append | Write-Output
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Scriptout missing user(s)$(if(-not $WhatIf){' and create on DR'}).." | Tee-Object $LogFile -Append | Write-Output

        $missing_users_prod = @()
        $missing_users_prod += $prod_users | Where-Object {$_.name -cin $missing_users}
        foreach ($user in $missing_users_prod)
        {
            $user_def = $user.tsql_add
            if ($OutputPath) { $user_def + "`rGO `r " | Out-File -Append -filepath $outfile  -ErrorAction stop }

            if (-not $WhatIf) {
                ExecuteNonQuery -SqlInstance $dr_server -Query $user_def -Database $database;
            }
        }

        if ($WhatIf) {
            "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Missing database user(s) scripted out in below file..`n'$outfile'" | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
        }
    }


    # 03 - Sync db Missing Functions from PROD to DR
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Compare functions b/w ($primary_server, $dr_server).." | Tee-Object $LogFile -Append | Write-Output
    $sql = @"
select name,schema_name(schema_id) AS schema_name,o.object_id,type_desc,create_date,modify_date, master.sys.fn_repl_hash_binary(convert(varbinary(max),ltrim(rtrim(m.definition)))) as hash_id
from sys.objects o
join sys.sql_modules m on m.object_id = o.object_id
WHERE type in ('FN') order by type,name;
"@
    $prod_functions = @()
    $prod_functions += ExecuteQuery -SqlInstance $primary_server -Query $sql -Database $database;
    $dr_functions = @()
    $dr_functions += ExecuteQuery -SqlInstance $dr_server -Query $sql -Database $database;

    #Get missing functions list in DR
    $missing_functions = @()
    $missing_functions += (Compare-Object -CaseSensitive -ReferenceObject $prod_functions -DifferenceObject $dr_functions -Property name, schema_name | where-object { $_.SideIndicator -eq "<=" })
    
    #$missing_functions_ids = @()
    if ($missing_functions.Count -gt 0)
    {
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => $($missing_functions.Count) missing function(s) found." | Tee-Object $LogFile -Append | Write-Output
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Scriptout missing function(s)$(if(-not $WhatIf){' and create on DR'}).." | Tee-Object $LogFile -Append | Write-Output
        foreach ($func in $missing_functions)
        {
            $func_def = ($smoprod.Databases[$database].UserDefinedFunctions | Where-Object { $_.Name -ceq $func.Name -and $_.Schema -ceq $func.schema_name }).Script()
            $func_def = $func_def -ireplace ("SET ANSI_NULLS ON|SET QUOTED_IDENTIFIER ON|SET QUOTED_IDENTIFIER OFF|SET ANSI_NULLS OFF", "")
            if ($OutputPath) { $func_def + "`rGO `r " | Out-File -Append -filepath $outfile  -ErrorAction stop }

            if (-not $WhatIf) {
                ExecuteNonQuery -SqlInstance $dr_server -Query $func_def -Database $database;
            }
        }

        if ($WhatIf) {
            "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Missing function(s) scripted out in below file..`n'$outfile'" | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
        }
    }

    # 04 - Sync functions from PROD which are different in Definition with DR
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Find changed functions b/w ($primary_server, $dr_server).." | Tee-Object $LogFile -Append | Write-Output
    $changed_functions_prod = @()
    $changed_functions_prod += Compare-Object -CaseSensitive -ReferenceObject $prod_functions -DifferenceObject $dr_functions -Property name, schema_name, hash_id | 
                                    where-object { $_.SideIndicator -eq "<=" -and ($missing_functions.Count -eq 0 -or $_.name -cnotin $($missing_functions.name)) }
    if ($changed_functions_prod.Count -gt 0)
    {
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => $($changed_functions_prod.Count) changed function(s) found." | Tee-Object $LogFile -Append | Write-Output
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Scriptout changed function(s)$(if(-not $WhatIf){' and apply on DR'}).." | Tee-Object $LogFile -Append | Write-Output
        foreach ($func in $changed_functions_prod)
        {
            $func_def = ($smoprod.Databases[$database].UserDefinedFunctions | Where-Object { $_.Name -ceq $func.Name -and $_.Schema -ceq $func.schema_name }).Script() -ireplace ("CREATE PROCEDURE |CREATE PROC ", "ALTER PROCEDURE ")
            $func_def = $func_def -ireplace ("SET ANSI_NULLS ON|SET QUOTED_IDENTIFIER ON|SET QUOTED_IDENTIFIER OFF|SET ANSI_NULLS OFF", "")
            $func_def = $func_def.Trim()

            if ($OutputPath) { $func_def + "`rGO `r " | Out-File -Append -filepath $outfile  -ErrorAction stop }

            if (-not $WhatIf) {
                ExecuteNonQuery -SqlInstance $primary_server -Query $func_def -Database $database;
                ExecuteNonQuery -SqlInstance $dr_server -Query $func_def -Database $database;
            }
        }

        if ($WhatIf) {
            "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Changed Prod function(s) scripted out in below file..`n'$outfile'" | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
        }
    }


    # 05 - Sync db Procedures from PROD to DR
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Compare Procedures b/w ($primary_server, $dr_server).." | Tee-Object $LogFile -Append | Write-Output
    $sql_procs = @"
select name,schema_name(schema_id) AS schema_name,o.object_id,type_desc,create_date,modify_date
		,master.sys.fn_repl_hash_binary(convert(varbinary(max),ltrim(rtrim(m.definition)))) as hash_id
from sys.objects o join sys.sql_modules m on m.object_id = o.object_id WHERE type in ('P') order by type,name;
"@
    $prod_procs = @()
    $prod_procs += ExecuteQuery -SqlInstance $primary_server -Query $sql_procs -Database $database;
    $dr_procs = @()
    $dr_procs += ExecuteQuery -SqlInstance $dr_server -Query $sql_procs -Database $database;

    # Get missing Procedures in DR
    $missing_procs = @()
    $missing_procs += (Compare-Object -CaseSensitive -ReferenceObject $prod_procs -DifferenceObject $dr_procs -Property name, schema_name | where-object { $_.SideIndicator -eq "<=" })
    
    #Write-Debug "Missing Stored Procedures"  

    # 06 - Scripting out missing Procedures in DR and Creating in DR 
    if ($missing_procs.Count -gt 0)
    {
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => $($missing_procs.Count) missing procedure(s) found." | Tee-Object $LogFile -Append | Write-Output
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Scriptout missing procedure(s)$(if(-not $WhatIf){' and create on DR'}).." | Tee-Object $LogFile -Append | Write-Output
        foreach ($proc in $missing_procs)
        {
            #$smoprod.Databases[$database].StoredProcedures[$proc.name].Script()
            $proc_def = ($smoprod.Databases[$database].StoredProcedures | Where-Object { $_.Name -ceq $proc.Name -and $_.Schema -ceq $proc.schema_name }).Script()
            $proc_def = $proc_def -ireplace ("SET ANSI_NULLS ON|SET QUOTED_IDENTIFIER ON|SET QUOTED_IDENTIFIER OFF|SET ANSI_NULLS OFF", "")
            
            if ($OutputPath) { $proc_def + "`rGO `r " | Out-File -Append -filepath $outfile  -ErrorAction stop }

            if (-not $WhatIf) {
                ExecuteNonQuery -SqlInstance $dr_server -Query $proc_def -Database $database;
                #Invoke-Sqlcmd -SqlInstanceInstance $dr_server -Query $proc_def -Database $database
            }
        }

        if ($WhatIf) {
            "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Missing procedure(s) scripted out in below file..`n'$outfile'" | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
        }
    }

    # 07 - Sync procedures from PROD which are different in Definition with DR
    $changed_procs_prod = @()
    $changed_procs_prod += Compare-Object -CaseSensitive -ReferenceObject $prod_procs -DifferenceObject $dr_procs `
                                        -Property name, schema_name, hash_id | 
                                    where-object { $_.SideIndicator -eq "<=" -and ($missing_procs.Count -eq 0 -or $_.name -cnotin $($missing_procs.name)) }
    if ($changed_procs_prod.Count -gt 0)
    {
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => $($changed_procs_prod.Count) changed procedure(s) found." | Tee-Object $LogFile -Append | Write-Output
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Scriptout changed procedure(s)$(if(-not $WhatIf){' and apply on DR'}).." | Tee-Object $LogFile -Append | Write-Output
        foreach ($proc in $changed_procs_prod)
        {
            $proc_def = ($smoprod.Databases[$database].StoredProcedures | Where-Object { $_.Name -ceq $proc.Name -and $_.Schema -ceq $proc.schema_name }).Script() -ireplace ("CREATE PROCEDURE |CREATE PROC ", "ALTER PROCEDURE ")
            $proc_def = $proc_def -ireplace ("SET ANSI_NULLS ON|SET QUOTED_IDENTIFIER ON|SET QUOTED_IDENTIFIER OFF|SET ANSI_NULLS OFF", "")
            $proc_def = $proc_def.Trim()

            if ($OutputPath) { $proc_def + "`rGO `r " | Out-File -Append -filepath $outfile  -ErrorAction stop }

            if (-not $WhatIf) {
                ExecuteNonQuery -SqlInstance $primary_server -Query $proc_def -Database $database;
                ExecuteNonQuery -SqlInstance $dr_server -Query $proc_def -Database $database;
            }
        }

        if ($WhatIf) {
            "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Changed Prod procedure(s) scripted out in below file..`n'$outfile'" | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
        }
    }


    # 08 - Script out object levelpermissions for db in PROD and execute in DR
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Sync $database database object level permissions.." | Tee-Object $LogFile -Append | Write-Output
    $sql = @"
select [tsql_grant_permission] = 'IF '+(CASE WHEN class_desc = 'SCHEMA' 
											then 'SCHEMA_ID('''+schema_name(perm.major_id)+''') IS NOT NULL '
											else 'OBJECT_ID('''+quotename(schema_name(obj.schema_id)) +'.'+ quotename(obj.name)+''') IS NOT NULL  '
											end) +
        CASE WHEN perm.state <> 'W' THEN perm.state_desc ELSE 'GRANT' END +SPACE(1) + 
        perm.permission_name + ' ON '+
        (case when class_desc = 'SCHEMA' then ' SCHEMA::'+quotename(schema_name(perm.major_id)) else quotename(schema_name(obj.schema_id))+'.'+quotename(obj.name) end) +' TO '+
        QUOTENAME(usr.name)  COLLATE database_default +
        CASE WHEN perm.state <> 'W' THEN SPACE(0) ELSE SPACE(1) + 'WITH GRANT OPTION' END +
        ';'
		--,quotename(schema_name(obj.schema_id))+'.'+quotename(obj.name)
		--,perm.* ,usr.* ,obj.*
FROM sys.database_permissions AS perm
JOIN sys.database_principals AS usr
	ON perm.grantee_principal_id = usr.principal_id  
JOIN sys.objects as obj 
	ON major_id = obj.object_id
where perm.major_id>0
AND object_name(perm.major_id) IS NOT NULL
"@
    $dbobject_permissions = @()
    $dbobject_permissions += ExecuteQuery -SqlInstance $primary_server -Database $database -Query $sql | Select-Object -ExpandProperty tsql_grant_permission

    foreach ($perm in $dbobject_permissions)
    {
        if ($OutputPath) { $perm | Out-File -Append -filepath $outfile  -ErrorAction stop }
        if (-not $WhatIf) {
            ExecuteNonQuery -SqlInstance $dr_server -Query $perm -Database $database;
        }
    }    

    if($WhatIf) {
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => TSQL Output scripted out in below file..`n'$outfile'" | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
    }
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(FINISH)", "$cmdCallStack => Completed on ($primary_server ~ $dr_server) for [$database]." | Tee-Object $LogFile -Append | Write-Output
}
