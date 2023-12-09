Remove-Module HadrSync -ErrorAction SilentlyContinue; Remove-Module DbaUtil -ErrorAction SilentlyContinue;
Get-Variable -Scope local | Remove-Variable -ErrorAction SilentlyContinue; $Error.Clear(); Clear-Host;

E:\Ajay\git\dba\DOMAIN1\powershell\modules\HadrSync\Wrappers\Wrapper-SyncMetaData.ps1 -Environment DOMAIN1 `
        -OutputPath 'E:\Ajay\git\dba\DOMAIN1\powershell\modules\HadrSync\Logs' `
        -WhatIf #-Debug

#C:\Users\Public\Documents\git\dba\DOMAIN1\powershell\modules\HadrSync\Wrappers\Wrapper-SyncMetaData.ps1 -Environment DOMAIN1 -WhatIf #-Debug
#C:\Users\Public\Documents\git\dba\DOMAIN2\powershell\Commons\Modules\HadrSync\Wrappers\Wrapper-SyncMetaData.ps1 -Environment DOMAIN2 -WhatIf #-Debug
#D:\Ajay\git\dba\DOMAIN2\powershell\Commons\Modules\HadrSync\Wrappers\Wrapper-SyncMetaData-Dev.ps1 -Environment DOMAIN2 #-WhatIf #-Debug

<#
Import-Module C:\Users\Public\Documents\git\dba\DOMAIN1\powershell\modules\HadrSync\HadrSync.psm1 -DisableNameChecking
sync_meta_data -WhatIf `
        -primary_server 'SQLPROD6' -dr_server 'SQLDR6' `
        -OutputPath 'E:\Ajay\git\dba\DOMAIN1\powershell\modules\HadrSync\Logs' `
        -LogFile 'E:\Ajay\git\dba\DOMAIN1\powershell\modules\HadrSync\Logs\sync_meta_data - 2021-08-25 04.45.53.txt' `
        -Debug
#>
<#
Remove-Module HadrSync
Remove-Module DbaUtil

import-module C:\Users\Public\Documents\git\dba\DOMAIN1\powershell\modules\HadrSync
#>
