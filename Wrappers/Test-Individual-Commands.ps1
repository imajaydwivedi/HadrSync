# Clear session variables & Remove module from Memory
Remove-Module HadrSync -ErrorAction SilentlyContinue; Remove-Module DbaUtil -ErrorAction SilentlyContinue;
Get-Variable -Scope local | Remove-Variable -ErrorAction SilentlyContinue; $Error.Clear(); Clear-Host;

# Import Module
$ModulePath = 'E:\Ajay\git\dba\DOMAIN1\powershell\modules\HadrSync'
Import-Module (Join-Path $ModulePath "HadrSync.psm1") -DisableNameChecking
Import-Module "$MDS_DbaUtilPath\DbaUtil.psm1" -DisableNameChecking
Get-ChildItem -Path $MDS_LogsPath | Remove-Item -Force

# Execute one function for Server Pair
$LogFile = (Join-Path $MDS_LogsPath "sync_meta_data - $Dtmm.txt")
sync_meta_data -ErrorAction Stop `
        -primary_server 'SQLPROD6' -dr_server 'SQLDR6' `
        -OutputPath $MDS_LogsPath ` `
        -LogFile $LogFile `
        -WhatIf #-Debug

<#

# Execute all function for Server Pair
$LogFile = (Join-Path $MDS_LogsPath "sync_meta_data - $Dtmm.txt")
sync_meta_data -ErrorAction Stop `
        -primary_server 'SQLPROD6' -dr_server 'SQLDR6' `
        -OutputPath $MDS_LogsPath ` `
        -LogFile $LogFile `
        -WhatIf

# Execute one function for Server Pair
$LogFile = (Join-Path $MDS_LogsPath "sync_SQL_logins - $Dtmm.txt")
sync_SQL_logins -ErrorAction Stop `
        -primary_server 'SQLPROD6' -dr_server 'SQLDR6' `
        -OutputPath $MDS_LogsPath ` `
        -LogFile $LogFile `
        -WhatIf

# Execute one function for Server+Database Pair
$LogFile = (Join-Path $MDS_LogsPath "Create-LinkedServerOnDR - $Dtmm.txt")
sync_database_objects -ErrorAction Stop `
        -primary_server 'SQLPROD6' -dr_server 'SQLDR6' -database 'DBA' `
        -OutputPath $MDS_LogsPath ` `
        -LogFile $LogFile `
        -WhatIf

#>