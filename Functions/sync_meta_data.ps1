function sync_meta_data
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [string]$primary_server,
        [Parameter(Mandatory=$true)]
        [string]$dr_server,
        [Parameter(Mandatory=$true)]
        [string]$OutputPath,
        [Parameter(Mandatory = $true)]
        [string]$LogFile,
        [switch]$WhatIf
    )
    [bool]$Debug = $false
    if($PSBoundParameters.ContainsKey('Debug') -and $PSBoundParameters.Debug.Equals($true)) { [bool]$Debug = $true }
    if($true) { 
        '*' * 50; $PSBoundParameters | Out-String | Tee-Object -FilePath $LogFile -Append | Write-Host -ForegroundColor Cyan;
        "`$startTime = '$startTime'" | Out-String | Tee-Object -FilePath $LogFile -Append | Write-Host -ForegroundColor Cyan;
        "`$Dtmm = '$Dtmm'" | Out-String | Tee-Object -FilePath $LogFile -Append | Write-Host -ForegroundColor Cyan;
        '*' * 50;
    }

    $Script = $MyInvocation.MyCommand.Name
    if([String]::IsNullOrEmpty($Script)) {
        $Script = 'sync_meta_data.ps1'
    }
    $callStack = Get-PSCallStack
    $cmdCallStack = ($callStack[1..0]).Command -join ' => '

    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Processing ($primary_server ~ $dr_server)$(if($Debug){" in DEBUG mode"}).." | Tee-Object $LogFile -Append | Write-Output

    $errMsgSrv = @()
    $errMsgSrv.Clear()

    # Create linked server for Primary on DR as its prerequisites
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Invoke 'Create-LinkedServerOnDR'.." | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
    Try { Create-LinkedServerOnDR @PSBoundParameters; }
    catch { $errMsgCmd = $_.ToString() + $_.InvocationInfo.PositionMessage; $errMsgCmd = "Failure in '$cmdCallStack' for ($primary_server ~ $dr_server) with below error message -`n$errMsgCmd"; $errMsgSrv += $errMsgCmd;
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(ERROR)", "$cmdCallStack => $errMsgCmd" | Write-Host -ForegroundColor Red;
    }

    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Invoke 'sync_SQL_logins'.." | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
    Try { sync_SQL_logins @PSBoundParameters; }
    catch { $errMsgCmd = $_.ToString() + $_.InvocationInfo.PositionMessage; $errMsgCmd = "Failure in '$cmdCallStack' for ($primary_server ~ $dr_server) with below error message -`n$errMsgCmd"; $errMsgSrv += $errMsgCmd;
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(ERROR)", "$cmdCallStack => $errMsgCmd" | Write-Host -ForegroundColor Red;
    }
    
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Invoke 'sync_SQL_roles'.." | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
    Try { sync_SQL_roles @PSBoundParameters; }
    catch { $errMsgCmd = $_.ToString() + $_.InvocationInfo.PositionMessage; $errMsgCmd = "Failure in '$cmdCallStack' for ($primary_server ~ $dr_server) with below error message -`n$errMsgCmd"; $errMsgSrv += $errMsgCmd;
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(ERROR)", "$cmdCallStack => $errMsgCmd" | Write-Host -ForegroundColor Red;
    }
    
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Invoke 'sync_database_objects' for [master].." | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
    Try { sync_database_objects @PSBoundParameters -database "master"; }
    catch { $errMsgCmd = $_.ToString() + $_.InvocationInfo.PositionMessage; $errMsgCmd = "Failure in '$cmdCallStack' for ($primary_server ~ $dr_server) with below error message -`n$errMsgCmd"; $errMsgSrv += $errMsgCmd;
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(ERROR)", "$cmdCallStack => $errMsgCmd" | Write-Host -ForegroundColor Red;
    }
    
    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Invoke 'sync_database_objects' for [DBA].." | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
    Try { sync_database_objects @PSBoundParameters -database "DBA"; }
    catch { $errMsgCmd = $_.ToString() + $_.InvocationInfo.PositionMessage; $errMsgCmd = "Failure in '$cmdCallStack' for ($primary_server ~ $dr_server) with below error message -`n$errMsgCmd"; $errMsgSrv += $errMsgCmd;
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(ERROR)", "$cmdCallStack => $errMsgCmd" | Write-Host -ForegroundColor Red;
    }

    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Invoke 'sync_SQL_server_permissions'.." | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
    Try { sync_SQL_server_permissions @PSBoundParameters; }
    catch { $errMsgCmd = $_.ToString() + $_.InvocationInfo.PositionMessage; $errMsgCmd = "Failure in '$cmdCallStack' for ($primary_server ~ $dr_server) with below error message -`n$errMsgCmd"; $errMsgSrv += $errMsgCmd;
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(ERROR)", "$cmdCallStack => $errMsgCmd" | Write-Host -ForegroundColor Red;
    }

    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Invoke 'sync_SQL_linked_server'.." | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
    Try { sync_SQL_linked_server @PSBoundParameters; }
    catch { $errMsgCmd = $_.ToString() + $_.InvocationInfo.PositionMessage; $errMsgCmd = "Failure in '$cmdCallStack' for ($primary_server ~ $dr_server) with below error message -`n$errMsgCmd"; $errMsgSrv += $errMsgCmd;
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(ERROR)", "$cmdCallStack => $errMsgCmd" | Write-Host -ForegroundColor Red;
    }

    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Invoke 'sync_SQL_database_permissions' for [DBA].." | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
    Try { sync_SQL_database_permissions @PSBoundParameters -database "DBA"; }
    catch { $errMsgCmd = $_.ToString() + $_.InvocationInfo.PositionMessage; $errMsgCmd = "Failure in '$cmdCallStack' for ($primary_server ~ $dr_server) with below error message -`n$errMsgCmd"; $errMsgSrv += $errMsgCmd;
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(ERROR)", "$cmdCallStack => $errMsgCmd" | Write-Host -ForegroundColor Red;
    }

    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Invoke 'sync_SQL_database_permissions' for [sandbox].." | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
    Try { sync_SQL_database_permissions @PSBoundParameters -database "sandbox"; }
    catch { $errMsgCmd = $_.ToString() + $_.InvocationInfo.PositionMessage; $errMsgCmd = "Failure in '$cmdCallStack' for ($primary_server ~ $dr_server) with below error message -`n$errMsgCmd"; $errMsgSrv += $errMsgCmd;
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(ERROR)", "$cmdCallStack => $errMsgCmd" | Write-Host -ForegroundColor Red;
    }

    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Invoke 'sync_SQL_database_permissions' for [txnref_scratchpad].." | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
    Try { sync_SQL_database_permissions @PSBoundParameters -database "txnref_scratchpad"; }
    catch { $errMsgCmd = $_.ToString() + $_.InvocationInfo.PositionMessage; $errMsgCmd = "Failure in '$cmdCallStack' for ($primary_server ~ $dr_server) with below error message -`n$errMsgCmd"; $errMsgSrv += $errMsgCmd;
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(ERROR)", "$cmdCallStack => $errMsgCmd" | Write-Host -ForegroundColor Red;
    }

    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Invoke 'sync_SQL_login_triggers'.." | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
    Try { sync_SQL_login_triggers @PSBoundParameters; }
    catch { $errMsgCmd = $_.ToString() + $_.InvocationInfo.PositionMessage; $errMsgCmd = "Failure in '$cmdCallStack' for ($primary_server ~ $dr_server) with below error message -`n$errMsgCmd"; $errMsgSrv += $errMsgCmd;
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(ERROR)", "$cmdCallStack => $errMsgCmd" | Write-Host -ForegroundColor Red;
    }

    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Invoke 'sync_SQL_server_configuration'.." | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
    Try { sync_SQL_server_configuration @PSBoundParameters; }
    catch { $errMsgCmd = $_.ToString() + $_.InvocationInfo.PositionMessage; $errMsgCmd = "Failure in '$cmdCallStack' for ($primary_server ~ $dr_server) with below error message -`n$errMsgCmd"; $errMsgSrv += $errMsgCmd;
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(ERROR)", "$cmdCallStack => $errMsgCmd" | Write-Host -ForegroundColor Red;
    }

    #"{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Invoke 'sync_SQL_server_resource_governor_config'.." | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
    #sync_SQL_server_resource_governor_config @PSBoundParameters

    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Invoke 'set_simple_recovery_for_non_mirrored_databases'.." | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
    Try { set_simple_recovery_for_non_mirrored_databases @PSBoundParameters; }
    catch { $errMsgCmd = $_.ToString() + $_.InvocationInfo.PositionMessage; $errMsgCmd = "Failure in '$cmdCallStack' for ($primary_server ~ $dr_server) with below error message -`n$errMsgCmd"; $errMsgSrv += $errMsgCmd;
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(ERROR)", "$cmdCallStack => $errMsgCmd" | Write-Host -ForegroundColor Red;
    }

    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Invoke 'sync_auto_stats_config'.." | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
    Try { sync_auto_stats_config @PSBoundParameters; }
    catch { $errMsgCmd = $_.ToString() + $_.InvocationInfo.PositionMessage; $errMsgCmd = "Failure in '$cmdCallStack' for ($primary_server ~ $dr_server) with below error message -`n$errMsgCmd"; $errMsgSrv += $errMsgCmd;
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(ERROR)", "$cmdCallStack => $errMsgCmd" | Write-Host -ForegroundColor Red;
    }

    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Invoke 'sync_connection_limit_config'.." | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
    Try { sync_connection_limit_config @PSBoundParameters; }
    catch { $errMsgCmd = $_.ToString() + $_.InvocationInfo.PositionMessage; $errMsgCmd = "Failure in '$cmdCallStack' for ($primary_server ~ $dr_server) with below error message -`n$errMsgCmd"; $errMsgSrv += $errMsgCmd;
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(ERROR)", "$cmdCallStack => $errMsgCmd" | Write-Host -ForegroundColor Red;
    }

    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Invoke 'update_tempdb_catalog'.." | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
    Try { update_tempdb_catalog @PSBoundParameters; }
    catch { $errMsgCmd = $_.ToString() + $_.InvocationInfo.PositionMessage; $errMsgCmd = "Failure in '$cmdCallStack' for ($primary_server ~ $dr_server) with below error message -`n$errMsgCmd"; $errMsgSrv += $errMsgCmd;
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(ERROR)", "$cmdCallStack => $errMsgCmd" | Write-Host -ForegroundColor Red;
    }

    "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(INFO)", "$cmdCallStack => Invoke 'sync_SQL_jobs'.." | Tee-Object $LogFile -Append | Write-Host -ForegroundColor Cyan
    Try { sync_SQL_jobs @PSBoundParameters; }
    catch { $errMsgCmd = $_.ToString() + $_.InvocationInfo.PositionMessage; $errMsgCmd = "Failure in '$cmdCallStack' for ($primary_server ~ $dr_server) with below error message -`n$errMsgCmd"; $errMsgSrv += $errMsgCmd;
        "{0} {1,-8} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", "(ERROR)", "$cmdCallStack => $errMsgCmd" | Write-Host -ForegroundColor Red;
    }

    # Generate error once all functions are done
    if($errMsgSrv.Count -gt 0) {
        $msg = $errMsgSrv -join "`n$('-'*50)`n"
        $Global:ErrorMessages = $Global:ErrorMessages + $errMsgSrv;
        $msg | Write-Host -ForegroundColor Red
        throw $msg
    }
}
