function sync_SQL_roles
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
        $Script = 'sync_SQL_roles.ps1'
    }
    $callStack = Get-PSCallStack
    $cmdCallStack = ($callStack[1..0]).Command -join ' => '

    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Processing ($primary_server ~ $dr_server)$(if($Debug){" in DEBUG mode"}).." | Tee-Object $LogFile -Append | Write-Output

    $filename = "HadrSync__"+$($Script.Replace('.ps1',''))+"__"+$primary_server.Replace('/', '_') + "__ScriptOut__$Dtmm.sql"
    $outfile = Join-Path -Path $OutputPath -ChildPath $filename
    
    #module to sync server level roles for primary to dr

    
    #$server_roles=@("bulkadmin","dbcreator","diskadmin","processadmin","securityadmin","setupadmin","sysadmin")
    #the role public has to be omitted as it assigned to each new login created
    $tsqlServerRoles = "SELECT name FROM sys.server_principals where type_desc='SERVER_ROLE' and name <>'public'"
    $server_roles = @()
    $server_roles += (ExecuteQuery -SqlInstance $primary_server -Query $tsqlServerRoles | Select-Object -ExpandProperty name)
    
    #Write-Debug "Stop before role loop"
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Loop through Server roles, and add role members on $dr_server.." | Tee-Object $LogFile -Append | Write-Output
    foreach ($role in $server_roles)
    {
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Create role [$role] on $dr_server if missing.." | Tee-Object $LogFile -Append | Write-Output
        $tsqlCreateRole = @"
if not exists (select * from sys.server_principals where type_desc='SERVER_ROLE' and name = '$role')
	CREATE SERVER ROLE [$role];

"@
        If ($WhatIf) {
            "$tsqlCreateRole" | Tee-Object $outfile -Append | Out-Null
        }
        else {
            ExecuteNonQuery -SqlInstance $dr_server -Query $tsqlCreateRole
        }

        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Add members of [$role] role on $dr_server.." | Tee-Object $LogFile -Append | Write-Output
        $tsqlRoleMembers = @"
SELECT [ServerRole] = role.name, [MemberName] = member.name, [MemberSID] = member.sid
FROM sys.server_role_members
JOIN sys.server_principals AS role
    ON sys.server_role_members.role_principal_id = role.principal_id
JOIN sys.server_principals AS member
    ON sys.server_role_members.member_principal_id = member.principal_id
WHERE role.name = '$role'
"@
        $resultRoleMembers = @()
        $resultRoleMembers += ExecuteQuery -SqlInstance $primary_server -Query $tsqlRoleMembers
        $rolemembers = @()
        if($resultRoleMembers.Count -gt 0) {
            $rolemembers += ($resultRoleMembers.MemberName | where { ($_ -notlike "NT*") -AND ($_ -notlike "BUILTIN*") -AND ($_ -notlike "DBEXT*") -AND ($_ -ne "sa") -AND ($_ -ne "DBABSNYC1\urseag-admin") })
        }

        foreach ($member in $rolemembers) {
            $sqlAddRoleMember = "IF EXISTS (SELECT 1 FROM sys.syslogins WHERE name = '$member')  EXEC sp_addsrvrolemember '$member', '$role' ;"
            If ($WhatIf) {
                "$sqlAddRoleMember" | Tee-Object $outfile -Append | Out-Null
            }
            else {
                ExecuteNonQuery -SqlInstance $dr_server -Query $sqlAddRoleMember
            }
        }

        if($rolemembers.Count -gt 0 -and $WhatIf) {
            "`n" | Out-File $outfile -Append
        }
    }

    if($WhatIf) {
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => TSQL Output scripted out in below file..`n'$outfile'" | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
    }
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(FINISH)", "$cmdCallStack => Completed on ($primary_server ~ $dr_server)." | Tee-Object $LogFile -Append | Write-Output
}

