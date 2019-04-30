[CmdletBinding()]
param (
    $DestinationPath = ".\ADReport.html",

    [Hashtable]
    $MailData
)

begin {
    function Check-Service {
        param (
    
            [Parameter(ParameterSetName = 'Servicios')]
            [String]
            $Service,
    
    
            [Parameter(ParameterSetName = 'Dcdiag')]
            [String]
            $Test,
            
            $timeout = 60,
    
            [String]
            $DC,
    
            $Report
            
        )
                
        process {
    
            $Language = @{
                es = "super\w+ la prueba $Test"
                en = "passed test $Test"
            }
    
            $UI = (Get-UICulture).Parent.Name
    
            $valueString = $Language[$UI]
    
            if ($PsCmdlet.ParameterSetName -eq 'Servicios') {
                $ScriptBlock = { get-service -ComputerName $($args[0]) -Name $($args[1]) -ErrorAction SilentlyContinue } 
                
                $Argument = $Service
                    
            } # if
            else {
                $ScriptBlock = { dcdiag /test:$($args[1]) /s:$($args[0]) }
                $Argument = $Test
            } # else
    
    
            $serviceStatus = start-job -scriptblock $ScriptBlock -ArgumentList $DC, $Argument
            wait-job $serviceStatus -timeout $timeout | Out-Null
        
            if ($serviceStatus.state -like "Running") {
                Write-Warning "[PROCESS] $DC `t $Argument timeout"
                Add-Content $report "<td bgcolor= 'Yellow' align=center><B>$($Test)TimeOut</B></td>"
                stop-job $serviceStatus
            }
            else {
                $serviceStatus1 = Receive-job $serviceStatus
                $svcState = $serviceStatus1.status          
    
                if ($PsCmdlet.ParameterSetName -eq 'Servicios') {
                    if ($serviceStatus1.status -eq "Running") {
                        Write-Verbose "[PROCESS] $DC `t $($serviceStatus1.name) `t $($serviceStatus1.status)"
                        Add-Content $report "<td bgcolor= '#4BB543' align=center><B>$svcState</B></td>" 
                    }
                    elseif ($ServiceStatus1.status -eq "Stopped") { 
                        Write-Warning "$DC `t $($serviceStatus1.name) `t $($serviceStatus1.status)"
                        Add-Content $report "<td bgcolor= 'Red' align=center><B>$svcState</B></td>" 
                    }
                    else {
                        Write-Warning "$DC `t $Service `t Not exist"
                        Add-Content $report "<td bgcolor= 'Yellow' align=center><B>NotHaveService</B></td>" 
                        
                    }
    
                } # if parameter set
                else {
                    if ($serviceStatus1 -match $valueString) {
                        Write-Verbose "[PROCESS] $DC `t $Test Test passed "
                        Add-Content $report "<td bgcolor= '#4BB543' align=center><B>Passed</B></td>"
                    }
                    else {
                        Write-Warning "$DC `t $test Test Failed"
                        Add-Content $report "<td bgcolor= 'Red' align=center><B>Fail</B></td>"
                    } # else if test
                } # else 
    
            } # if
    
        } # Process
    } # function
    

    Write-Verbose "[BEGIN  ] Starting $($MyInvocation.MyCommand)"

} # begin

process {

    # Create file    
    if ((test-path $DestinationPath) -like $false) {
        new-item $DestinationPath -type file | out-null
    }

    
    # Retrieve Domain Controllers
    try {
        Import-Module ActiveDirectory -Verbose:$false -ErrorAction Stop
        $getForest = (Get-ADForest)
        $DCServers = (Get-ADForest).Domains | ForEach-Object { Get-ADDomainController -Filter * -Server $_ } | Select-Object -ExpandProperty Name
    }
    catch {
        try {
            $getForest = [syste.directoryservices.activedirectory.Forest]::GetCurrentForest()
            $DCServers = $getForest.domains | ForEach-Object { $_.DomainControllers } | ForEach-Object { $_.HostName }
        }
        catch {
            Write-Error $_
            break
        }

    }

    $timeout = 60
        
    $report = $DestinationPath
    Clear-Content $report 
        
    $header = @"
        <html>
        <head> 
        <meta http-equiv='Content-Type' content='text/html; charset=iso-8859-1'>
        <title>AD Status Report</title> 
        <STYLE TYPE="text/css">
        <!--
        td {
                font-family: Tahoma;    
                font-size: 11px;
                border-top: 1px solid #999999;
                border-right: 1px solid #999999;
                border-bottom: 1px solid #999999;
                border-left: 1px solid #999999;
                padding-top: 0px;
                padding-right: 0px;
                padding-bottom: 0px;
                padding-left: 0px;
        }
        body {
                margin-left: 5px;    
                margin-top: 5px;
                margin-right: 0px;
                margin-bottom: 10px;
                
                table {
                        border: thin solid #000000;    
                }
                -->
                </style>
                </head>
                
                <body>
                <b><font face="Arial" size="5"></font></b><hr size="7" color="#EB9C12">
                <font face="Arial" size="3"><b>Active Directory Health Check | Algeiba IT |</b> <A HREF='https://www.algeiba.com/'>https://www.algeiba.com/</A></font><br>
                <font face="Arial" size="2">Reporte creado el dia $(Get-Date)</font>
                <br>
                <br>
                
                <table width='100%'>
                <tr bgcolor='#7BA7C7'>
                <td colspan='7' height='25' align='center'>
                <font face='Arial' color='#FFFFFF' size='3'>Forest: $($GetForest.Name) </font>
                </td>
                </tr>
                </table>
                
                <table width='100%'>
                <tr bgcolor='#cc0000'>
                <td width='5%' color='#ffffff' align='center'><B>Identity</B></td>
                <td width='10%' color='#ffffff' align='center'><B>PingSTatus</B></td>
                <td width='10%' color='#ffffff' align='center'><B>NetlogonService</B></td>
                <td width='10%' color='#ffffff' align='center'><B>NTDSService</B></td> 
                <td width='10%' color='#ffffff' align='center'><B>DNSServiceStatus</B></td>
                <td width='10%' color='#ffffff' align='center'><B>NetlogonsTest</B></td>
                <td width='10%' color='#ffffff' align='center'><B>ReplicationTest</B></td>
                <td width='10%' color='#ffffff' align='center'><B>ServicesTest</B></td>
                <td width='10%' color='#ffffff' align='center'><B>AdvertisingTest</B></td>
                <td width='10%' color='#ffffff' align='center'><B>FSMOCheckTest</B></td>
                
                </tr>
"@
                
    add-content $report $header

    # analize domain controllers
    $test = 'NetLogons', 'Replications', 'Services', 'Advertising', 'FsmoCheck'
    $Services = 'Netlogon', 'NTDS', 'DNS'
    foreach ($DC in $DCServers) {
        $Identity = $DC
        Add-Content $report "<tr>"
        if ( Test-Connection -ComputerName $DC -Count 1 -ErrorAction SilentlyContinue ) {
            Write-Verbose "[PROCESS] $DC `t PING SUCCESS"
            
            Add-Content $report "<td bgcolor= 'GainsBoro' align=center>  <B> $Identity</B></td>" 
            Add-Content $report "<td bgcolor= '#4BB543' align=center>  <B>Success</B></td>" 
			
            # Checking services
            Foreach ($S in $Services) {
                Check-Service -Service $S -DC $DC -report $report
                
            } # foreach services
            
            # Executing tests
            Foreach ($T in $Test) {
                Check-Service -Test $T -DC $DC -Report $report
            } # foreach tests
            
        } 
        else {
            Write-Verbose "[PROCESS] $DC `t PING FAIL"
            Add-Content $report "<td bgcolor= 'GainsBoro' align=center>  <B> $Identity</B></td>" 

            $Count = $Services.count + $test.count + 1
            1..$Count | ForEach-Object {
                Add-Content $report "<td bgcolor= 'Red' align=center>  <B>Ping Fail</B></td>" 
            }
        } # else if ping        
                        
    } # Foreach
                
    $CloseTags = @"
    </tr>
    </table>
    </body>
    </html>
"@
    
    Add-Content $report $CloseTags
                
} # process

end {
    
    if ($PSBoundParameters.ContainsKey('MailData')) {
        
        try {
            $MailData.Body = Get-Content $report | Out-String
            $MailData.BodyAsHtml = $True
            $Maildata.ErrorAction = 'Stop'
            Send-MailMessage @Maildata 
            
        }
        Catch {
            Write-Warning "Couldn't send mail"
            
        } # try catch
        
    } # if psbound
    
    Write-Verbose "[END    ] Ending $($MyInvocation.MyCommand)"
} # end