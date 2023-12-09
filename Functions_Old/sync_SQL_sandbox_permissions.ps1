function sync_SQL_sandbox_permissions($primary_server, $dr_server)
{
    #This method syncs sandbox permissions from the primary server to the DR server
    Begin { Write-Host "Starting fn::sync_SQL_sandbox_permissions for Primary: $primary_server and DR: $dr_server" -ForegroundColor Cyan }
    Process {
 
        $db = "sandbox"
        # checking the existence of sandbox
        $sql = "select count(1) from master.sys.databases where name = 'sandbox' and state_desc='ONLINE'"
        $primary_sandbox_exists_token = (ExecuteQuery -server $primary_server -query $sql).Column1
        if ($primary_sandbox_exists_token -eq 1) { Write-Host "sandbox exist on $primary_server" } else { Write-Output "sandbox does not exist on $primary_server ,skipping fn:sync_SQL_sandbox_permissions"; return }

        $dr_sandbox_exists_token = (ExecuteQuery -server $dr_server -query $sql).Column1
        if ($dr_sandbox_exists_token -eq 1) { Write-Host "sandbox exist on $dr_server" } else { Write-Output "sandbox does not exist on $dr_server ,skipping fn:sync_SQL_sandbox_permissions"; return }


        #sync sql users
        $sql = "SELECT 'IF NOT EXISTS (SELECT 1 from sys.sysusers where name='''+name+''') CREATE USER [' + name + '] FOR LOGIN ['+name+'];' + NCHAR(10),name FROM sandbox.sys.database_principals WHERE type='S' AND  principal_id > 4";
        $sandbox_sql_users = ExecuteQuery -server $primary_server -query $sql -db $db

        if ($sandbox_sql_users.Column1.count -gt 0) {
            foreach ($user in $sandbox_sql_users) {
                #ExecuteNonQuery -server $dr_server -query $user.Column1 -db $db;
                #$user.Column1;
                If ($WhatIf) { $user.Column1; }
                else { ExecuteNonQuery -server $dr_server -query $user.Column1 -db $db; }
            }
        }
                                              
        #sync windows users
        $sql = "SELECT 'IF NOT EXISTS (SELECT 1 from sys.sysusers where name='''+dp.name+''') CREATE USER [' + dp.name + '] FOR LOGIN ['+sp.name+'];',dp.name FROM sandbox.sys.database_principals dp JOIN sys.server_principals sp ON sp.sid=dp.sid WHERE dp.type IN ('G','U') AND dp.principal_id > 4"
        $sandbox_win_users = ExecuteQuery -server $primary_server -query $sql -db $db
        if ($sandbox_win_users.Column1.count -gt 0) {
            foreach ($user in $sandbox_win_users) {
                #ExecuteNonQuery -server $dr_server -query $user.Column1 -db $db;
                #$user.Column1;
                If ($WhatIf) { $user.Column1; }
                else { ExecuteNonQuery -server $dr_server -query $user.Column1 -db $db; }
            }
        }


        #sync roles
        $sql = "SELECT 'IF NOT EXISTS (SELECT 1 FROM sandbox.sys.database_principals WHERE name='''+name+''')  CREATE ROLE [' + name + '];'  FROM sandbox.sys.database_principals WHERE type='R' AND is_fixed_role=0 AND principal_id>0";
        $sandbox_roles = ExecuteQuery -server $primary_server -query $sql -db $db
        if ($sandbox_roles.Column1.count -gt 0) {
            foreach ($role in $sandbox_roles) {
                #ExecuteNonQuery -server $dr_server -query $role.Column1 -db $db;
                #$role.Column1;
                If ($WhatIf) { $role.Column1; }
                else { ExecuteNonQuery -server $dr_server -query $role.Column1 -db $db; }
            }
        }
     

        #sync role members
        $sql = "SELECT  'ALTER ROLE ' + QUOTENAME(USER_NAME(rm.role_principal_id), '') + '  ADD MEMBER '+QUOTENAME(USER_NAME(rm.member_principal_id), '')  +';'
FROM sandbox.sys.database_role_members AS rm
WHERE USER_NAME(rm.member_principal_id) NOT IN ('dbo','sys')
ORDER BY rm.role_principal_id ASC";
        $sandbox_role_members = ExecuteQuery -server $primary_server -query $sql -db $db
        if ($sandbox_role_members.Column1.count -gt 0) {
            foreach ($member in $sandbox_role_members) {
                #ExecuteNonQuery -server $dr_server -query $member.Column1 -db $db;
                #$member.Column1;
                If ($WhatIf) { $member.Column1; }
                else { ExecuteNonQuery -server $dr_server -query $member.Column1 -db $db; }
											                                          
            }
        }


        #sync database permissions
        $sql = "SELECT
CASE WHEN perm.state <> 'W' THEN perm.state_desc ELSE 'GRANT' END +
SPACE(1) + perm.permission_name + SPACE(1) + SPACE(1) + 'TO' + SPACE(1) +
QUOTENAME(usr.name) COLLATE database_default +
CASE WHEN perm.state <> 'W' THEN SPACE(0) ELSE SPACE(1) + 'WITH GRANT OPTION' END
+';'
-- + NCHAR(10)
FROM sandbox.sys.database_permissions AS perm
JOIN sandbox.sys.database_principals AS usr
ON perm.grantee_principal_id = usr.principal_id
AND perm.major_id = 0
WHERE usr.name NOT IN ('dbo','sys')
ORDER BY perm.permission_name ASC, perm.state_desc ASC";
        $sandbox_db_perms = ExecuteQuery -server $primary_server -query $sql -db $db
        if ($sandbox_db_perms.Column1.count -gt 0) {
            foreach ($perms in $sandbox_db_perms) {
                #ExecuteNonQuery -server $dr_server -query $perms.Column1 -db $db;
                #$perms.Column1;
                If ($WhatIf) { $perms.Column1; }
                else { ExecuteNonQuery -server $dr_server -query $perms.Column1 -db $db; }
            }
        }


        # sync schema permissions
        $sql = "SELECT state_desc+' '+permission_name+' ON '+class_desc+'::'+SCHEMA_NAME(major_id)+' TO '+QUOTENAME(USER_NAME(grantee_principal_id)) +';' FROM sys.database_permissions where class_desc = 'SCHEMA'";
        $sandbox_schema_perms = ExecuteQuery -server $primary_server -query $sql -db $db
        if ($sandbox_schema_perms.Column1.count -gt 0) {
            foreach ($schema in $sandbox_schema_perms) {
                #ExecuteNonQuery -server $dr_server -query $schema.Column1 -db $db;
                #$schema.Column1;
                If ($WhatIf) { $schema.Column1 }
                else { ExecuteNonQuery -server $dr_server -query $schema.Column1 -db $db; }
            }
        }

        #sync drop stale users
        $sql = "SELECT name from sys.sysusers";
        $primary_users = ExecuteQuery -server $primary_server -query $sql -db $db;
        $dr_users = ExecuteQuery -server $dr_server -query $sql -db $db;
        $dr_only_users = $dr_users.name | where-Object { if ($_ -cnotin $primary_users.name) { $_ } }

        if ($dr_only_users.count -gt 0) {
            foreach ($user in $dr_only_users) {
                $sql = "drop user [$user];"
                If ($WhatIf) { $sql }
                else { ExecuteNonQuery -server $dr_server -query $sql -db $db }
                #ExecuteNonQuery -server $dr_server -query $sql -db $db;
                #$sql
            }
        }
    }
    End { Write-Host "End fn::sync_SQL_sandbox_permissions for Primary: $primary_server and DR: $dr_server`n`n" -ForegroundColor Cyan }
}
