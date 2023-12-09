function ExecuteQuery
{
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true)]
        [string] $SqlInstance,
        [Parameter(Mandatory=$true)]
        $Query,
        [string] $Database = "master"
    )
    $localErrorMessage = $null

    $sqlconnection = new-object System.Data.SqlClient.SqlConnection("server=$SqlInstance;Database=$Database;Trusted_Connection=true");
    $sqlconnection.Open()
    $cmd = new-object System.Data.SqlClient.SqlCommand
    $cmd.Connection=$sqlconnection
    $cmd.CommandTimeout = 0;
    $cmd.CommandText=$Query
    $result = $cmd.ExecuteReader()
    $table = new-object System.Data.DataTable

    try {
        $table.Load($result)
    }
    catch {
        $localErrorMessage =  "Error::Server: $SqlInstance Db: $Database Query: $query Error: $_";
    }
    
    $sqlconnection.Close()
    
    if([String]::IsNullOrEmpty($localErrorMessage)) {
        $table
    }
    else {
        throw $localErrorMessage
    }

    <#
    function to get database results by running DQL operation for given Server,DB,SQL (Single line SELECT operations)
    #>
}
