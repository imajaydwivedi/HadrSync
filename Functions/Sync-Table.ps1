Function Sync-Table
{
    [CmdletBinding()]
    Param (
        [parameter(Mandatory = $true)]   [string] $source_server,
        [parameter(Mandatory = $true)]   [string] $source_db,
        [parameter(Mandatory = $true)]   [string] $source_schema,
        [parameter(Mandatory = $true)]   [string] $source_table,
        [parameter(Mandatory = $true)]   [string] $destination_server,
        [parameter(Mandatory = $true)]   [string] $destination_db,
        [parameter(Mandatory = $true)]   [string] $destination_schema,
        [parameter(Mandatory = $true)]   [string] $destination_table,
        [switch] $preserve_identity,
        [switch] $truncate_destination
    )
    <# function to BulkCopy the data from one table to other table between the servers #>
    $source_sqlconnection = new-object System.Data.SqlClient.SqlConnection("server=$source_server;Database=$source_db;Trusted_Connection=true");
    $source_sqlconnection.Open()
    $source_cmd = new-object System.Data.SqlClient.SqlCommand
    $source_cmd.Connection = $source_sqlconnection
    $source_cmd.CommandTimeout = 0;
    $source_cmd.CommandText = "select * from [$source_schema].[$source_table] with (nolock)"
    $source_reader = $source_cmd.ExecuteReader()


    if ($truncate_destination) {
        Invoke-sqlcmd -ServerInstance $destination_server -Database $destination_db -Query "TRUNCATE TABLE [$destination_schema].[$destination_table]"
        #ExecuteNonQuery -SqlInstance $destination_server -Database $destination_db -Query "TRUNCATE TABLE [$destination_schema].[$destination_table]"
    }


    if ($preserve_identity) {
        $destinationConStrg = "server=$destination_server;Database=$destination_db;Trusted_Connection=true"
        $bulkCopy = New-Object Data.SqlClient.SqlBulkCopy($destinationConStrg, [System.Data.SqlClient.SqlBulkCopyOptions]::KeepIdentity)
    }
    else {
        $destination_sqlconnection = new-object System.Data.SqlClient.SqlConnection("server=$destination_server;Database=$destination_db;Trusted_Connection=true");
        $destination_sqlconnection.Open()
        $bulkCopy = new-object ("Data.SqlClient.SqlBulkCopy") $destination_sqlconnection;
    }
    $destination_FQTN = "[" + $destination_schema + "].[" + $destination_table + "]"
    $bulkCopy.DestinationTableName = $destination_FQTN;

    $bulkCopy.BatchSize = 5000;
    $bulkCopy.BulkCopyTimeout = 0;
    Trap { "Error::Error: $_"; Continue } $bulkCopy.WriteToServer($source_reader)

    $source_reader.close()
    $source_sqlconnection.Close()
    if ($destination_sqlconnection) { $destination_sqlconnection.Close() }
    $bulkCopy.Close()
}