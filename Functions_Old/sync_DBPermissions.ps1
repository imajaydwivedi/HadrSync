function sync_DBPermissions($primary_server, $dr_server) {
    #This method syncs sandbox permissions from the primary server to the DR server
    Begin { Write-Host "Starting fn::sync_DBPermissions for Primary: $primary_server and DR: $dr_server" -ForegroundColor Cyan }
    Process {

        $dblist = @('txnref_scratchpad')
        foreach ($db in $dblist) {
            Write-Host "Starting fn::sync_DBPermissions for the database [$db]." -ForegroundColor Cyan

            # checking the existence of $db on primary
            $sql = "select count(1) from master.sys.databases where name = '$db' and state_desc='ONLINE'"
            $primary_DB_exists_token = (ExecuteQuery -server $primary_server -query $sql).Column1
            if ($primary_DB_exists_token -eq 1) { Write-Host "The database [$db] exist on $primary_server" }
            else { Write-Host "The database [$db] does not exist on $primary_server ,skipping fn:sync_DBPermissions for [$db]."; continue }
            # checking the existence of $db on DR
            $dr_DB_exists_token = (ExecuteQuery -server $dr_server -query $sql).Column1
            if ($dr_DB_exists_token -eq 1) { Write-Host "The database [$db] exist on $dr_server" }
            else { Write-Output "The database [$db] does not exist on $dr_server ,skipping fn:sync_DBPermissions for [$db]."; continue }


            #sync sql users
            $sql = "SELECT 'IF NOT EXISTS (SELECT 1 from sys.sysusers where name='''+name+''') 
      CREATE USER [' + name + '] FOR LOGIN ['+name+'];' + NCHAR(10),name 
      FROM sys.database_principals WHERE type='S' AND  principal_id > 4";
            $DB_sql_users = ExecuteQuery -server $primary_server -query $sql -db $db
            if ($DB_sql_users.Column1.count -gt 0) {
                foreach ($user in $DB_sql_users) {
                    If ($WhatIf) { $user.Column1; }
                    else { ExecuteNonQuery -server $dr_server -query $user.Column1 -db $db; }
                }
            }
                                              
            #sync windows users
            $sql = "SELECT 'IF NOT EXISTS (SELECT 1 from sys.sysusers where name='''+dp.name+''') 
      CREATE USER [' + dp.name + '] FOR LOGIN ['+sp.name+'];',dp.name 
      FROM sys.database_principals dp 
      JOIN sys.server_principals sp 
      ON sp.sid=dp.sid WHERE dp.type IN ('G','U') 
      AND dp.principal_id > 4"
            $DB_win_users = ExecuteQuery -server $primary_server -query $sql -db $db
            if ($DB_win_users.Column1.count -gt 0) {
                foreach ($user in $DB_win_users) {
                    If ($WhatIf) { $user.Column1; }
                    else { ExecuteNonQuery -server $dr_server -query $user.Column1 -db $db; }
                }
            }


            #sync DB Roles
            $sql = "SELECT 'IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name='''+name+''')  
      CREATE ROLE [' + name + '];'  
      FROM sys.database_principals 
      WHERE type='R' 
      AND is_fixed_role=0 
      AND principal_id>0";
            $DB_roles = ExecuteQuery -server $primary_server -query $sql -db $db
            if ($DB_roles.Column1.count -gt 0) {
                foreach ($role in $DB_roles) {
                    If ($WhatIf) { $role.Column1; }
                    else { ExecuteNonQuery -server $dr_server -query $role.Column1 -db $db; }
                }
            }
     


            #sync DB Role members
            #$sql="SELECT  'ALTER ROLE ' + QUOTENAME(USER_NAME(rm.role_principal_id), '') + '  ADD MEMBER '+QUOTENAME(USER_NAME(rm.member_principal_id), '')  +';'
            $sql = "SELECT  'EXEC sp_addrolemember ''' + USER_NAME(rm.role_principal_id) + ''','''+
      USER_NAME(rm.member_principal_id)+''';'
      FROM sys.database_role_members AS rm
      WHERE USER_NAME(rm.member_principal_id) NOT IN ('dbo','sys')
      ORDER BY rm.role_principal_id ASC";
            $DB_role_members = ExecuteQuery -server $primary_server -query $sql -db $db
            if ($DB_role_members.Column1.count -gt 0) {
                foreach ($member in $DB_role_members) {
                    If ($WhatIf) { $member.Column1; }
                    else { ExecuteNonQuery -server $dr_server -query $member.Column1 -db $db; }
                }
            }



            # sync schema permissions
            $sql = "SELECT state_desc+' '+permission_name+' ON '+class_desc+'::'+
      SCHEMA_NAME(major_id)+' TO '+QUOTENAME(USER_NAME(grantee_principal_id)) +';' 
      FROM sys.database_permissions where class_desc = 'SCHEMA'";
            $DBschema_perms = ExecuteQuery -server $primary_server -query $sql -db $db
            if ($DBschema_perms.Column1.count -gt 0) {
                foreach ($schema in $DBschema_perms) {
                    If ($WhatIf) { $schema.Column1 }
                    else { ExecuteNonQuery -server $dr_server -query $schema.Column1 -db $db; }
                }
            }




            #sync database permissions
            $sql = "SELECT
CASE WHEN perm.state <> 'W' 
THEN perm.state_desc ELSE 'GRANT' END +
SPACE(1) + perm.permission_name + SPACE(1) + SPACE(1) + 'TO' + SPACE(1) +
QUOTENAME(usr.name) COLLATE database_default +
CASE WHEN perm.state <> 'W' 
THEN SPACE(0) 
ELSE SPACE(1) + 'WITH GRANT OPTION' END
+';'
-- + NCHAR(10)
FROM sys.database_permissions AS perm
JOIN sys.database_principals AS usr
ON perm.grantee_principal_id = usr.principal_id
AND perm.major_id = 0
WHERE usr.name NOT IN ('dbo','sys')
ORDER BY perm.permission_name ASC, perm.state_desc ASC";
            $DB_perms = ExecuteQuery -server $primary_server -query $sql -db $db
            if ($DB_perms.Column1.count -gt 0) {
                foreach ($perms in $DB_perms) {
                    If ($WhatIf) { $perms.Column1; }
                    else { ExecuteNonQuery -server $dr_server -query $perms.Column1 -db $db; }
                }
            }




            #sync DB Object Permissions
            $sql = "SELECT 
--usr.name Member,
CASE WHEN perm.state <> 'W' THEN perm.state_desc ELSE 'GRANT' END +          
SPACE(1) + perm.permission_name + SPACE(1) + 'ON ' +          
QUOTENAME(SCHEMA_NAME(obj.schema_id)) + '.' + QUOTENAME(obj.name) +          
CASE WHEN cl.column_id IS NULL THEN SPACE(0) ELSE '(' + QUOTENAME(cl.name) +           
')' END + SPACE(1) + 'TO' + SPACE(1) + QUOTENAME(usr.name)          
COLLATE database_default + CASE WHEN perm.state <> 'W' THEN SPACE(0) ELSE SPACE(1) +          
'WITH GRANT OPTION' END + NCHAR(10)      
FROM sys.database_permissions AS perm          
INNER JOIN          
sys.objects AS obj          
ON perm.major_id = obj.[object_id]          
INNER JOIN          
sys.database_principals AS usr          
ON perm.grantee_principal_id = usr.principal_id          
LEFT JOIN          
sys.columns AS cl          
ON cl.column_id = perm.minor_id AND cl.[object_id] = perm.major_id          
WHERE usr.name NOT IN ('dbo','sys')  and  class_desc = 'OBJECT_OR_COLUMN'             
ORDER BY perm.permission_name ASC, perm.state_desc ASC";
            $DB_Objectperms = ExecuteQuery -server $primary_server -query $sql -db $db
            if ($DB_Objectperms.Column1.count -gt 0) {
                foreach ($Objectperms in $DB_Objectperms) {
                    If ($WhatIf) { $Objectperms.Column1; }
                    else { ExecuteNonQuery -server $dr_server -query $Objectperms.Column1 -db $db; }
                }
            }




            #sync drop stale users
            $sql = "SELECT name from sys.sysusers";
            $primary_users = ExecuteQuery -server $primary_server -query $sql -db $db;
            $dr_users = ExecuteQuery -server $dr_server -query $sql -db $db;
            $dr_only_users = $dr_users.name | where-Object { if ($_ -cnotin $primary_users.name) { $_ } }

            if ($dr_only_users.count -gt 0) {
                foreach ($user in $dr_only_users) {
                    #$sql="drop user [$user];"
                    $sql = "IF EXISTS (SELECT 1 FROM sys.schemas WHERE [name] = '$user') DROP SCHEMA [$user];DROP USER [$user];"

                    If ($WhatIf) { $sql }
                    else { ExecuteNonQuery -server $dr_server -query $sql -db $db }
                }
            }
        }

    }

    End { Write-Host "End fn::sync_DBPermissions for Primary: $primary_server and DR: $dr_server`n`n" -ForegroundColor Cyan }
}
