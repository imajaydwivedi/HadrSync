function main( ) {
    $sql = "SELECT Dataserver AS prod_data_server,
       DRDataserver AS dr_data_server,
	   1 AS is_hadr_sync_enabled
FROM   DbaCentral.dbo.server_inventory
WHERE  IsActive = 1
AND    Env = 'PROD'
AND    Monitor = 'Yes'
AND    ServerType = 'DB'
AND    HasDR = 'Yes'
AND    Dataserver not like '%SQLPROD%' and Dataserver not like '%DBREPLTOA1.lab.com,13601%' and Dataserver not like 'SHAREDMGMT3.win.lab.com%'

             ";

    $server_list = ExecuteQuery -server dbmonitor -query $sql
    foreach ($server in $server_list) {
        $prod_server = $server.prod_data_server;
        $dr_server = $server.dr_data_server;
        # Start: Check Servers Status
        $sql_check_status = "SELECT 'Available' AS Status";
        $prod_server_status = ExecuteQuery -server $prod_server -query $sql_check_status
        $dr_server_status = ExecuteQuery -server $dr_server -query $sql_check_status
        if (($prod_server_status.Status -ne "Available") -or ($dr_server_status.Status -ne "Available")) { continue; }
        # End: Check Servers Status
        Write-Host "`n`n`nStarting hadr_sync for PROD: $prod_server, DR: $dr_server`n" -ForegroundColor Cyan
        sync_meta_data -primary_server $prod_server -dr_server $dr_server -outputpath $outputpath -WhatIf $WhatIf
    }


}
