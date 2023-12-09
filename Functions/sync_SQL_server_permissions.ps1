function sync_SQL_server_permissions
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
        $Script = 'sync_SQL_server_permissions.ps1'
    }
    $callStack = Get-PSCallStack
    $cmdCallStack = ($callStack[1..0]).Command -join ' => '

    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Processing ($primary_server ~ $dr_server)$(if($Debug){" in DEBUG mode"}).." | Tee-Object $LogFile -Append | Write-Output

    $filename = "HadrSync__"+$($Script.Replace('.ps1',''))+"__"+$primary_server.Replace('/', '_') + "__ScriptOut__$Dtmm.sql"
    $outfile = Join-Path -Path $OutputPath -ChildPath $filename
    
    $sql = @"
select	[is_exists_code] = 'IF EXISTS (SELECT 1 FROM sys.server_principals p where p.name='''+name COLLATE DATABASE_DEFAULT +''' and p.type_desc = '''+ppl.type_desc COLLATE DATABASE_DEFAULT +''') ',
		[perm_type] = 'GRANT ', permission_name, [to_login] = ' to ['+name +']' 
		--, ppl.*
from sys.server_permissions perm
inner join sys.server_principals ppl  
	on perm.grantee_principal_id = ppl.principal_id
where permission_name !='CONNECT SQL' and class_desc = 'SERVER'
and name not like '%#%'and name not like '%NT%' and name not like '%BUILTIN%'
and state_desc = 'GRANT'
"@
    #$sql
    $srv_roles = ExecuteQuery -SqlInstance $primary_server -Query $sql

    foreach ($role in $srv_roles) {
        $sqlAddRole = $role.is_exists_code + $role.perm_type + " " + $role.permission_name + " " + $role.to_login + ";"
        If ($WhatIf) {
            "$sqlAddRole" | Tee-Object $outfile -Append | Out-Null
        }
        else {
            ExecuteNonQuery -SqlInstance $dr_server -Query $sqlAddRole
        }
    }
    
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => TSQL Output scripted out in below file..`n'$outfile'" | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(FINISH)", "$cmdCallStack => Completed on ($primary_server ~ $dr_server)." | Tee-Object $LogFile -Append | Write-Output
}
