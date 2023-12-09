function update_tempdb_catalog
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
        $Script = 'update_tempdb_catalog.ps1'
    }
    $callStack = Get-PSCallStack
    $cmdCallStack = ($callStack[1..0]).Command -join ' => '

    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Processing ($primary_server ~ $dr_server)$(if($Debug){" in DEBUG mode"}).." | Tee-Object $LogFile -Append | Write-Output

    $filename = "HadrSync__"+$($Script.Replace('.ps1',''))+"__"+$primary_server.Replace('/', '_') + "__ScriptOut__$Dtmm.sql"
    $outfile = Join-Path -Path $OutputPath -ChildPath $filename

    
    # Validate if servers are ARC
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Check if servers are ARC.." | Tee-Object $LogFile -Append | Write-Output
    $serversql = @"
SELECT Dataserver as ServerName, FriendlyName
FROM DbaCentral.dbo.server_inventory 
WHERE IsActive=1 and ServerType='DB'
and Dataserver not like '%dbmonitor%'
and Description not like '%A.P. Lab & Co.%'
and monitor ='Yes'
and ( FriendlyName in ('$primary_server','$dr_server')
    or Dataserver in ('$primary_server','$dr_server')
    )
"@
    $servers = @()
    $servers += Invoke-Sqlcmd -ServerInstance $InventoryServer -Database $InventoryDb -Query $serversql

    #Write-Debug "Inside $Script"
    if($servers.Count -eq 0) {
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(WARN)", "$cmdCallStack => Either servers are not ARC, or are not Active." | Tee-Object $LogFile -Append | Write-Output
        return
    }

    # Generate alert if tempdb files not on standard path
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(WARN)", "$cmdCallStack => Check tempdb file path.." | Tee-Object $LogFile -Append | Write-Output
    $updatetempdb = @"
set nocount on;

if OBJECT_ID('tempdb..#table') is not null
	drop table #table

create table #table (
	server varchar(100)
	,sql nvarchar(MAX)
	,[currentpath] varchar(100)
	,[status] bit default 0
	)

declare @Logpath varchar(150) = (
		select top 1 SUBSTRING(physical_name, 1, (LEN(physical_name) - CONVERT(int, (CHARINDEX('\', REVERSE(physical_name))))) + 1) as location
		from tempdb.sys.database_files
		where type_desc = 'LOG'
		)
declare @datapath varchar(150) = (
		select top 1 SUBSTRING(physical_name, 1, (LEN(physical_name) - CONVERT(int, (CHARINDEX('\', REVERSE(physical_name))))) + 1) as location
		from tempdb.sys.database_files
		where type_desc = 'ROWS'
		)
declare @SQL nvarchar(MAX)

if (lower(@Logpath) <> lower('Z:\TempDB\'))
begin
	insert into #table (
		[currentpath]
		,server
		,[sql]
		)
	select @Logpath
		,CONVERT(varchar(max),SERVERPROPERTY('MachineName'))
		,'ALTER DATABASE tempdb Modify File (Name = ' + name + ', FILENAME = N''' + replace(physical_name, @Logpath, 'Z:\TempDB\') + ''');'
	from tempdb.sys.database_files
	where type_desc = 'LOG'
end

if (loweR(@datapath) <> lower('Z:\TempDB\'))
begin
	insert into #table (
		[currentpath]
		,server
		,[sql]
		)
	select @datapath
		,CONVERT(varchar(max),SERVERPROPERTY('MachineName'))
		,'ALTER DATABASE tempdb Modify File (Name = ' + name + ', FILENAME = N''' + replace(physical_name, @Logpath, 'Z:\TempDB\') + ''');'
	from tempdb.sys.database_files
	where type_desc = 'ROWS'
end

if exists (
		select 1
		from #table
		)
begin
	while exists (
			select 1
			from #table
			where status = 0
			)
	begin
		select top 1 @SQL = [sql]
		from #table
		where status = 0

		--EXEC sp_executesql @SQL
		update #table
		set [status] = 1
		where [sql] = @SQL
	end
end

select server as server_name
	,sql as sql_command
	,currentpath as current_path
from #table
"@

    foreach ($srv in $servers)
    {
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => $($srv.FriendlyName) => Check tempdb file path.." | Tee-Object $LogFile -Append | Write-Output
        $data = @()
        $data += Invoke-Sqlcmd -ServerInstance $srv.FriendlyName -Database master -Query $updatetempdb
        if ($data.Count -gt 0) {
            "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(WARN)", "$cmdCallStack => $($srv.FriendlyName) => $($data.Count) tempdb files not on path 'Z:\TempDB\'." | Tee-Object $LogFile -Append | Write-Output
            
            $result = $data | Format-Table -AutoSize | Out-String
            $result | Tee-Object $outfile -Append | Out-Null

            $Body = "The following tempdb files are not in the standard format. Please use following sql to modify the file structure.`n";
            $Body = $body + "Please use sql to modify the file structure.`n"
            $Body = $Body + $result;
            $message = $Body

            if(-not $WhatIf) {
                Raise-DbaServiceNowAlert -Summary "Check-TempdbFileStructure-$($srv.FriendlyName)" -Severity HIGH -Description $message `
                                    -AlertSourceHost $srv.FriendlyName -AlertTargetHost $srv.FriendlyName `
                                    -Alertkb "http://wiki.lab.com/display/TECHDOCS/Check-tempdbfilestructure"
            }
            else {
                "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(WARN)", "$cmdCallStack => $($srv.FriendlyName) => $message" | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Magenta
            }
        }
    }

    if($WhatIf) {
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Script Output in below file..`n'$outfile'" | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
    }
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(FINISH)", "$cmdCallStack => Completed on ($primary_server ~ $dr_server)." | Tee-Object $LogFile -Append | Write-Output
}
