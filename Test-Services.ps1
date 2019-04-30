param (
    [Parameter(Mandatory=$True)]
    [String[]]
    $Computers
)
$NoImportantServices = @('sppsvc', 'wbiosrvc', 'mapsbroker', 'remoteregistry')

Describe -Name 'Infrastructure Health Check' {


    Foreach ($Computer in $Computers) {

        Context -Name "$Computer AVAILABILITY" {
            It -Name "$Computer Responds to Ping" {
                $Ping = Test-NetConnection -ComputerName $Computer
                $Ping.PingSucceeded | Should -Be $true
            }
        
            Context -Name "$Computer SERVICES" {

                $Services = Get-WmiObject -Class Win32_Service -ComputerName $Computer |
                Where-Object { $_.StartMode -eq 'Auto' -and $_.name -notin $NoImportantServices }
                Foreach ($Service in $Services) {
                    It -Name "$($Service.Name) Should Be Running" {
                        $Status = Get-Service $Service.name -ComputerName $Computer -ErrorAction Stop
                        $Status.Status | Should -BeExactly 'Running'
                    }
                    
                }
                
            }
            $Command = {
                Get-WmiObject -Class win32_volume | Where-Object { $_.DriveType -eq '3' -and -not [string]::IsNullOrEmpty($_.DriveLetter) }
            }

            $Arguments = @{
                ScriptBlock = $Command 
                ComputerName = $Computer
            } 

            if ($Computer -in @('localhost',$Env:COMPUTERNAME)) {

                $Arguments.Remove('ComputerName')

            }

            $vols = Invoke-Command @Arguments
           
            context 'Capacity' {
               
                foreach ($volume in $Vols) {
                    $driveLetter = $volume.DriveLetter
                    it "Drive [$driveLetter] has at least 10% free space" {
                        ($volume.FreeSpace / $volume.Capacity) -ge  0.1| Should -Be $true
                    }
                }
            }

        } 
    }
    
}
    
# $report =  Invoke-Pester .\Test-Infra.ps1 -Show Fails -PassThru
# Invoke-Pester .\Test-Infra.ps1 -Show Fails 