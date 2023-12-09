<# BEGIN: Sync git files from Local to DBMONITOR #>
$Local_DOMAIN1 = 'C:\Users\Public\Documents\git\dba\DOMAIN1\powershell\modules\HadrSync\'
$Local_LAB = 'C:\Users\Public\Documents\git\dba\DOMAIN2\powershell\Commons\Modules\HadrSync\'

$Remote_DOMAIN1 = '\\dbmonitor.contoso.com\E$\Ajay\git\dba\DOMAIN1\powershell\modules\HadrSync\'
$Remote_LAB = '\\dbmonitor.lab.com\D$\Ajay\git\dba\DOMAIN1\powershell\modules\HadrSync\'

robocopy "$Local_DOMAIN1" "$Remote_DOMAIN1" /XD "$($Source).git" /e /it /is /MT:4
#robocopy "$Remote_DOMAIN1" "$Local_DOMAIN1" /XD "$($Source).git" /e /it /is /MT:4
#robocopy "$Local_DOMAIN1" "$Local_LAB" /XD "$($Source).git" /e /it /is /MT:4
#robocopy "$Local_DOMAIN1" "$Remote_LAB" /XD "$($Source).git" /e /it /is /MT:4
<# END: Sync files & folder from dbmonitor to Local #>