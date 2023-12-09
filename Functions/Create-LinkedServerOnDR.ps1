function Create-LinkedServerOnDR
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
        $Script = 'Create-LinkedServerOnDR.ps1'
    }
    $callStack = Get-PSCallStack
    #$cmdCallStack = ($callStack[($callStack.Count-2)..0]).Command -join ' => '
    $cmdCallStack = ($callStack[1..0]).Command -join ' => '

    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Processing ($primary_server ~ $dr_server)$(if($Debug){" in DEBUG mode"}).." | Tee-Object $LogFile -Append | Write-Output

    $filename = "HadrSync__"+$($Script.Replace('.ps1',''))+"__"+$primary_server.Replace('/', '_') + "__ScriptOut__$Dtmm.sql"
    $outfile = Join-Path -Path $OutputPath -ChildPath $filename
    
    $tsqlPrimaryLinkedServer = @"
set nocount on;
declare @server_name sysname = '$primary_server';
if not exists (select * from sys.servers s where s.name = @server_name)
begin
	EXEC master.dbo.sp_addlinkedserver @server = @server_name, @srvproduct=N'SQL Server';
	EXEC master.dbo.sp_addlinkedsrvlogin @rmtsrvname=@server_name,@useself=N'True',@locallogin=NULL,@rmtuser=NULL,@rmtpassword=NULL;
	EXEC master.dbo.sp_serveroption @server=@server_name, @optname=N'collation compatible', @optvalue=N'false';
	EXEC master.dbo.sp_serveroption @server=@server_name, @optname=N'data access', @optvalue=N'true';
	EXEC master.dbo.sp_serveroption @server=@server_name, @optname=N'dist', @optvalue=N'false';
	EXEC master.dbo.sp_serveroption @server=@server_name, @optname=N'pub', @optvalue=N'false';
	EXEC master.dbo.sp_serveroption @server=@server_name, @optname=N'rpc', @optvalue=N'true';
	EXEC master.dbo.sp_serveroption @server=@server_name, @optname=N'rpc out', @optvalue=N'true';
	EXEC master.dbo.sp_serveroption @server=@server_name, @optname=N'sub', @optvalue=N'false';
	EXEC master.dbo.sp_serveroption @server=@server_name, @optname=N'connect timeout', @optvalue=N'0';
	EXEC master.dbo.sp_serveroption @server=@server_name, @optname=N'collation name', @optvalue=null;
	EXEC master.dbo.sp_serveroption @server=@server_name, @optname=N'lazy schema validation', @optvalue=N'false';
	EXEC master.dbo.sp_serveroption @server=@server_name, @optname=N'query timeout', @optvalue=N'0';
	EXEC master.dbo.sp_serveroption @server=@server_name, @optname=N'use remote collation', @optvalue=N'true';
	EXEC master.dbo.sp_serveroption @server=@server_name, @optname=N'remote proc transaction promotion', @optvalue=N'true';
end
"@
    ExecuteNonQuery -SqlInstance $dr_server -Query $tsqlPrimaryLinkedServer
    
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(FINISH)", "$cmdCallStack => Completed on ($primary_server ~ $dr_server)." | Tee-Object $LogFile -Append | Write-Output
}