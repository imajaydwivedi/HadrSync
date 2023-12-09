function ExecuteNonQuery
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
    #Trap {"Error::Server: $SqlInstance Db: $Database Query: $query Error: $_";Continue} $cmd.ExecuteNonQuery() | Out-Null
    #$sqlconnection.Close()

    try {
        $cmd.ExecuteNonQuery() | Out-Null
    }
    catch {
        $localErrorMessage =  "Error::Server: $SqlInstance Db: $Database Query: $query Error: $_";
    }
    
    $sqlconnection.Close()
    
    if(-not [String]::IsNullOrEmpty($localErrorMessage)) {
        throw $localErrorMessage
    }

    <#
        function to run SQL on DB which does DDL,DML operation for given Server,DB,SQL 
    #>
}