#HadrSync.psm1

# Establish and enforce coding rules in expressions, scripts, and script blocks.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$global:MDS_ModulePath = Split-Path $MyInvocation.MyCommand.Path -Parent;
$global:MDS_FunctionsPath = Join-Path $MDS_ModulePath 'Functions'
$global:MDS_PrivatePath = Join-Path $MDS_ModulePath 'Private'
$global:MDS_DependenciesPath = Join-Path $MDS_ModulePath 'Dependencies'
$global:MDS_LogsPath = Join-Path $MDS_ModulePath 'Logs'
$global:MDS_DbaUtilPath = "$MDS_ModulePath\..\DbaUtil"

# Declare Global Variables
$ErrorActionPreference = 'Stop'
$global:StartTime = Get-Date
$global:Dtmm = $startTime.ToString('yyyy-MM-dd HH.mm.ss')
$global:InventoryServer = 'dbmonitor.lab.com'
$global:InventoryDb = "DbaCentral"
$global:AlertKB = "http://wiki.lab.com/display/DBADocs/HadrSync"
$global:LogRetentionDays = 7
$global:ErrorMessages = @()

# Import functions into memory
foreach($file in Get-ChildItem -Path $MDS_FunctionsPath) {
    . ($file.FullName)
    "Importing file '$($file.FullName)'" | Write-Output
}
