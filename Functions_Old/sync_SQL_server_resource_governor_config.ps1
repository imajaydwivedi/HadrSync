function sync_SQL_server_resource_governor_config($primary_server, $dr_server) {
    Begin { Write-Host "Starting fn::sync_SQL_server_resource_governor_config for Primary: $primary_server and DR: $dr_server" -ForegroundColor Cyan }
    Process {

        $sql = "select classifier_function_id from sys.dm_resource_governor_configuration;"
        $resource_governor_id = (ExecuteQuery -server $primary_server -query $sql).classifier_function_id
        if ($resource_governor_id -eq 0) {
            Write-Host "Resource Governer not enabled on the Primary: $primary_server";
            return;
        }

        $sql =
        "disable trigger trg_delete_resource_governor on _resource_governor;
disable trigger trg_insert_resource_governor on _resource_governor;
disable trigger trg_update_resource_governor on _resource_governor;
truncate table  _resource_governor;
truncate table _resource_governor_history;"

        If ($WhatIf) { $sql }
        else { ExecuteNonQuery -server $dr_server -query $sql; }
        #ExecuteNonQuery -server $dr_server -query $sql;
        #$sql


        if ($primary_server.Toupper().contains(".WIN.lab.com")) { $primary = $primary_server.Toupper().replace(".WIN.lab.com", "") }
        elseif ($primary_server.contains("\")) { $primary = $primary_server.substring($primary_server.IndexOf("\") + 1) }
        else { $primary = $primary_server }
        $sql = "
insert into _resource_governor select * from $primary.master.dbo._resource_governor;
set identity_insert _resource_governor_history on;
insert into _resource_governor_history (resource_name,resource_type,workload_group,_td_transaction_date,_td_suser_name,_td_spid,_td_operation,_td_bl_id) select * from $primary.master.dbo._resource_governor_history";
        If ($WhatIf) { $sql }
        else { ExecuteNonQuery -server $dr_server -query $sql; }
        #ExecuteNonQuery -server $dr_server -query $sql;
        #$sql


        $sql =
        "enable trigger trg_delete_resource_governor on _resource_governor;
enable trigger trg_insert_resource_governor on _resource_governor;
enable trigger trg_update_resource_governor on _resource_governor;"
        If ($WhatIf) { $sql }
        else { ExecuteNonQuery -server $dr_server -query $sql; }
        #ExecuteNonQuery -server $dr_server -query $sql;
        #$sql
    }
    End { Write-Host "End fn::sync_SQL_server_resource_governor_config for Primary: $primary_server and DR: $dr_server`n`n" -ForegroundColor Cyan }
}

