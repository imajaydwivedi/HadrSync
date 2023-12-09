function mExecuteQuery($server, $query, $db = "master")
{ #function to get database results by running DQL operations for given Server,DB,SQL (Multi line SELECT operations)
    $sqlconnection = new-object System.Data.SqlClient.SqlConnection("server=$server;Database=$db;Trusted_Connection=true");
    $sqlconnection.Open()
    $cmd = new-object System.Data.SqlClient.SqlCommand
    $cmd.Connection = $sqlconnection
    $cmd.CommandTimeout = 0;
    $cmd.CommandText = $query
    $dataset = New-Object System.Data.DataSet
    $sqladapter = New-Object System.Data.SqlClient.SqlDataAdapter
    $sqladapter.SelectCommand = $cmd
    $sqladapter.Fill($dataset)
    $sqlconnection.Close()
    $dataset
}