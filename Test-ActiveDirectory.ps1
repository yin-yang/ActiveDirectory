# Based on https://github.com/EvotecIT/PesterInfrastructureTests 

# Requires -Module ActiveDirectory
# Requires -Module Pester

Describe -Name 'Domain Controller Infrastructure Test' {
    try {
        $Domains = (get-adforest -ErrorAction Stop).Domains
    }
    catch {
        $Domains = $null
    }

    It -Name 'Active Directory Forest is available' {
        $Domains | Should -Not -BeNullOrEmpty
    }
    if ($Domains -eq $null) { return }
    foreach ($Domain in $Domains) {
        try {
            $DomainControllers = (Get-ADDomainController -Server $Domain -Filter * -ErrorAction Stop | Select-Object HostName).HostName
        }
        catch {
            $DomainControllers = $null
        }
        It -Name 'Active Directory Domain is available' {
            $DomainControllers | Should -Not -BeNullOrEmpty
        }
        if ($DomainControllers -eq $null) { return }
        foreach ($dc in $DomainControllers) {
            Context -Name "$dc Availability" {

                It -Name "$dc Responds to Ping" {
                    $Ping = Test-NetConnection -ComputerName dc$
                    $Ping.PingSucceeded | Should -Be $true
                }
                It -Name "$dc Responds on Port 53" {
                    $Port = Test-NetConnection -ComputerName $dc -Port 53
                    $Port.TcpTestSucceeded | Should -Be $true
                }
                It -Name "$dc DNS Service is Running" {
                    $DNSsvc = Get-Service -ComputerName $dc 'DNS' -ErrorAction Stop
                    $DNSsvc.Status | Should -BeExactly 'Running'
                }
                It -Name "$dc ADDS Service is Running" {
                    $NTDSsvc = Get-Service -ComputerName $dc 'NTDS' -ErrorAction Stop
                    $NTDSsvc.Status | Should -BeExactly 'Running'
                }
                It -Name "$dc ADWS Service is Running" {
                    $ADWSsvc = Get-Service -ComputerName $dc 'ADWS' -ErrorAction Stop
                    $ADWSsvc.Status | Should -BeExactly 'Running'
                }
                It -Name "$dc KDC Service is Running" {
                    $KDomainControllersvc = Get-Service -ComputerName $dc 'kdc' -ErrorAction Stop
                    $KDomainControllersvc.Status | Should -BeExactly 'Running'
                }
                It -Name "$dc Netlogon Service is Running" {
                    $Netlogonsvc = Get-Service -ComputerName $dc 'Netlogon' -ErrorAction Stop
                    $Netlogonsvc.Status | Should -BeExactly 'Running'
                }
            }
            Context -Name "Replication Status" {
                It -Name "$dc Last Replication Result is 0 (Success)" {
                    $RepResult = Get-ADReplicationPartnerMetaData -Target "$dc" -PartnerType Both -Partition *
                    # using $null because success is 0, and that is considered a null value
                    $RepResult.LastReplicationResult | Should -BeIn $null, 0
                }
            }
            #room for future tests if needed
        }
        Context 'Replication Link Status' {

            $results = repadmin /showrepl * /csv | ConvertFrom-Csv # Get the results of all replications between allDomainControllers 

            $groups = $results | Group-Object -Property 'Source DSA' # Group the results by the source DC

            foreach ($sourcedsa in $groups) {
                # Create a context for each source DC

                Context "Source DSA = $($sourcedsa.Name)" {

                    $targets = $sourcedsa.Group # Assign the value of the groupings to another var since .Group doesn't implement IComparable

                    $targetdsa = $targets | Group-Object -Property 'Destination DSA' # Now group within this source DC by the destination DC (pulling naming contexts per source and destination together)

                    foreach ($target in $targetdsa ) {
                        # Create a context for each destination DSA

                        Context "Target DSA = $($target.Name)" {

                            foreach ($entry in $target.Group) {
                                # List out the results and check each naming context for failures

                                It "$($entry.'Naming Context') - should have zero replication failures" {
                                    $entry.'Number of failures' | Should Be 0
                                }
                            }
                        }
                    }
                }
            }
        }
    }

}