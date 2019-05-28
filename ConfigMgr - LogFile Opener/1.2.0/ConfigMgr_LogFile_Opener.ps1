<#
.SYNOPSIS
    Provides simple access to the ConfigMgr Client Logs using CMTrace.exe
.DESCRIPTION
    Provides simple access to the ConfigMgr Client Logs using CMTrace.exe
.PARAMETER CMTrace
    Specify the Path to CMTrace.exe
.PARAMETER Hostname
    Specify a Default hostname for direct connection. Otherwise the Tool will prompt you to specify a hostname.
.PARAMETER ClientLogFilesDir
    Specify the directory in which the ConfigMgr Client LogFiles are located. (e.g: "Program Files\CCM\Logs")
.PARAMETER DisableLogFileMerging
    If specified, the LogFiles won't get merged by CMTrace
.PARAMETER WindowStyle
    Specify the Window Style of CMTrace and File Explorer. Default value is 'normal'
.EXAMPLE
    .\ConfigMgr_LogFile_Opener.ps1 -CMTrace 'C:\temp\CMTrace.exe' -Hostname 'PC01' -ClientLogFilesDir 'Program Files\CCM\Logs' -DisableLogFileMerging -WindowStyle Maximized
.NOTES
    Script name:   ConfigMgr_LogFile_Opener.ps1
    Author:        @SimonDettling <msitproblog.com>
    Date modified: 2017-01-19
    Version:       1.2.0
#>

[CmdletBinding()]
Param(
    [Parameter(Mandatory=$false, HelpMessage='Specify the hostname for direct connection. Otherwise the Tool will prompt you to specify a hostname.')]
    [String] $Hostname = '',

    [Parameter(Mandatory=$false, HelpMessage='Specify the Path to CMTrace.exe')]
    [String] $CMTrace = 'C:\Windows\CMTrace.exe',

    [Parameter(Mandatory=$false, HelpMessage='Specify the directory in which the ConfigMgr Client Logfiles are located. (e.g: "Program Files\CCM\Logs")')]
    [String] $ClientLogFilesDir = 'C$\Windows\CCM\Logs',

    [Parameter(Mandatory=$false, HelpMessage="If specified, the LogFiles won't get merged by CMTrace")]
    [Switch] $DisableLogFileMerging,

    [Parameter(Mandatory=$false, HelpMessage="Specify the Window Style of CMTrace and File Explorer. Default value is 'normal'")]
    [ValidateSet('Minimized', 'Maximized', 'Normal')]
    [String] $WindowStyle = 'Normal'
)

# Add Forms Assembly for displaying error message popups
Add-Type -AssemblyName System.Windows.Forms | Out-Null

# Create Shell Object, for handling CMTrace Inputs. (Usage of the .NET Classes led to CMTrace Freezes.)
$shellObj = New-Object -ComObject WScript.Shell

# Contains the information if the connected device is remote or local
$hostnameIsRemote = $true

$logfileTable = @{
    'ccmsetup' = @{
        'path' = 'C$\Windows\ccmsetup\Logs'
        'logfiles' = 'ccmsetup.log'
    }
    'ccmupdate' = @{
        'path' = $clientLogfilesDir
        'logfiles' = '"ScanAgent.log" "UpdatesDeployment.log" "UpdatesHandler.log" "UpdatesStore.log" "WUAHandler.log"'
    }
    'winupdate' = @{
        'path' = 'C$\Windows'
        'logfiles' = 'WindowsUpdate.log'
    }
    'ccmappdiscovery' = @{
        'path' = $clientLogfilesDir
        'logfiles' = 'AppDiscovery.log'
    }
    'ccmappenforce' = @{
        'path' = $clientLogfilesDir
        'logfiles' = 'AppEnforce.log'
    }
    'ccmexecmgr' = @{
        'path' = $clientLogfilesDir
        'logfiles' = 'execmgr.log'
    }
    'ccmexec' = @{
        'path' = $clientLogfilesDir
        'logfiles' = 'CcmExec.log'
    }
    'ccmstartup' = @{
        'path' = $clientLogfilesDir
        'logfiles' = 'ClientIDManagerStartup.log'
    }
    'ccmpolicy' = @{
        'path' = $clientLogfilesDir
        'logfiles' = '"PolicyAgent.log" "PolicyAgentProvider.log" "PolicyEvaluator.log" "StatusAgent.log"'
    }
    'ccmepagent' = @{
        'path' = $clientLogfilesDir
        'logfiles' = 'EndpointProtectionAgent.log'
    }
    'ccmdownload' = @{
        'path' = $clientLogfilesDir
        'logfiles' = '"CAS.log" "CIDownloader.log" "DataTransferService.log"'
    }
    'ccmeval' = @{
        'path' = $clientLogfilesDir
        'logfiles' = 'CcmEval.log'
    }
    'ccminventory' = @{
        'path' = $clientLogfilesDir
        'logfiles' = '"InventoryAgent.log" "InventoryProvider.log"'
    }
    'ccmsmsts' = @{
        'path' = $clientLogfilesDir
        'logfiles' = 'smsts.log'
    }
    'ccmstatemessage' = @{
        'path' = $clientLogfilesDir
        'logfiles' = 'StateMessage.log'
    }
}

$ccmBuildNoTable = @{
    '7711' = '2012 RTM';
    '7804' = '2012 SP1';
    '8239' = '2012 SP2 / R2 SP1';
    '7958' = '2012 R2 RTM';
    '8325' = '1511';
    '8355' = '1602';
    '8412' = '1606';
    '8458' = '1610';
}

Function Open-LogFile ([String] $Action) {
    # Get action from Hash Table, and throw error if it does not exist
    $actionHandler = $logfileTable.GetEnumerator() | Where-Object {$_.Key -eq $action}
    If (!$actionHandler) {
        Invoke-MessageBox -Message "Action '$action' can not be found in Hash Table"
        Invoke-MainMenu
    }

    # Assign values from Hash Table
    $logfilePath = "\\$hostname\$($actionHandler.Value.path)"
    $logfiles = $actionHandler.Value.logfiles

    # Check if path is accessible
    If (!(Test-Path -Path $logfilePath)) {
        Invoke-MessageBox -Message "'$logfilePath' is not accessible!"
        Invoke-MainMenu
    }

    # Check if CMTrace exists
    If (!(Test-Path -Path $cmtrace)) {
        Invoke-MessageBox -Message "'$cmtrace' is not accessible!"
        Invoke-MainMenu
    }

    # Check if CMTrace was started at least once. This is needed to make sure that the initial FTA PopUp doesn't appear.
    If (!(Test-Path -Path 'HKCU:\Software\Microsoft\Trace32')) {
        Invoke-MessageBox -Message "CMTrace needs be started at least once. Click 'OK' to launch CMTrace, confirm all dialogs and try again." -Icon 'Warning'
        Invoke-CMTrace
    }

    # Write current path in Registry
    Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Trace32' -Value $logfilePath -Name 'Last Directory' -Force

    # Check if multiple files were specified
    If ($logfiles.contains('" "')) {
        # Start CMTrace and wait until it's open
        Start-Process -FilePath $cmtrace
        Start-Sleep -Seconds 1

        # Send CTRL+O to open the open file dialog
        $shellObj.SendKeys('^o')
        Start-Sleep -Seconds 1

        # Write logfiles name
        $shellObj.SendKeys($logfiles)

        # check if logfile merging is not disabled
        If (!$disableLogfileMerging) {
            # Navigate to Merge checkbox and enable it
            $shellObj.SendKeys('{TAB}{TAB}{TAB}{TAB}{TAB}')
            $shellObj.SendKeys(' ')
        }

        # Send ENTER
        $shellObj.SendKeys('{ENTER}')
    } Else {
        # Build full logfile path
        $fullLogfilePath = $logfilePath + '\' + $logfiles

        # Check if Logfile exists
        If (!(Test-Path -Path $fullLogfilePath)) {
            Invoke-MessageBox -Message "'$fullLogfilePath' is not accessible!"
            Invoke-MainMenu
        }

        # Open Logfile in CMTrace
        Start-Process -FilePath $cmtrace -ArgumentList $fullLogfilePath
    }

    # Wait until log file is loaded
    Start-Sleep -Seconds 1

    # Send CTRL + END to scroll to the bottom
    $shellObj.SendKeys('^{END}')

    # Check WindowStyle. NOTE: CMTrace can't be launched using the native 'WindowStyle' Attribute via Start-Process above.
    Switch ($windowStyle) {
        'Minimized' {$shellObj.SendKeys('% n')}
        'Maximized' {$shellObj.SendKeys('% x')}
    }

    # Set Empty path in registry
    Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Trace32' -Value '' -Name 'Last Directory' -Force

    Invoke-MainMenu
}

Function Open-Path ([String] $Path) {
    # build full path
    $logfilePath = "\\$hostname\$Path"

    # Check if path is accessible
    If (!(Test-Path -Path $logfilePath)) {
        Invoke-MessageBox -Message "'$logfilePath' is not accessible!"
    }

    # Open File explorer
    Start-Process -FilePath 'C:\Windows\explorer.exe' -ArgumentList $logfilePath -WindowStyle $windowStyle

    Invoke-MainMenu
}

Function Invoke-CMTrace {
    # Check if CMTrace exists
    If (!(Test-Path -Path $cmtrace)) {
        Invoke-MessageBox -Message "'$cmtrace' is not accessible!"
        Invoke-MainMenu
    }

    # Open Logfile in CMTrace
    Start-Process -FilePath $cmtrace
    Start-Sleep -Seconds 1

    # Check WindowStyle. NOTE: CMTrace can't be launched using the native 'WindowStyle' Attribute via Start-Process above.
    Switch ($windowStyle) {
        'Minimized' {$shellObj.SendKeys('% n')}
        'Maximized' {$shellObj.SendKeys('% x')}
    }

    Invoke-MainMenu
}

Function Invoke-ClientAction([String[]] $Action) {
    Try {
        # Set ErrorActionPreference stop stop, otherwise Try/Catch won't have an effect on Invoke-WmiMethod
        $ErrorActionPreference = 'Stop'

        foreach ($singleAction in $action) {
            # Trigger specified WMI Method on Client. Note: Invoke-Cim Command doesn't work here --> Error 0x8004101e
            If ($hostnameIsRemote) {
                Invoke-WmiMethod -ComputerName $hostname -Namespace 'root\CCM' -Class 'SMS_Client' -Name 'TriggerSchedule' -ArgumentList ('{' + $singleAction + '}') | Out-Null
            }
            Else {
                Invoke-WmiMethod -Namespace 'root\CCM' -Class 'SMS_Client' -Name 'TriggerSchedule' -ArgumentList ('{' + $singleAction + '}') | Out-Null
            }
        }

        # Display message box
        Invoke-MessageBox -Message 'The Client Action has been executed.' -Icon 'Info'
    }
    Catch {
        # Display error message in case of a failure and return to the client action menu
        $errorMessage = $_.Exception.Message
        Invoke-MessageBox -Message "Unable to execute the specified Client Action.`n`n$errorMessage"
    }

    Invoke-ClientActionMenu
}

Function Invoke-MessageBox([String] $Message, [String] $Icon = 'Error') {
    [System.Windows.Forms.MessageBox]::Show($message, 'ConfigMgr LogFile Opener', 'OK', $icon) | Out-Null
}

Function Get-ClientVersionString {
    Try {
        # Get client version from WMI
        If ($hostnameIsRemote) {
            $clientVersion = Get-CimInstance -ComputerName $hostname -Namespace 'root\CCM' -ClassName 'SMS_Client' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty 'ClientVersion'
        }
        Else {
            $clientVersion = Get-CimInstance -Namespace 'root\CCM' -ClassName 'SMS_Client' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty 'ClientVersion'
        }

        # Extract build number from client version
        $ccmBuildNo = $clientVersion.Split('.')[2]

        # Get BuildNo String from hash table
        $ccmBuildNoHandler = $ccmBuildNoTable.GetEnumerator() | Where-Object {$_.Key -eq $ccmBuildNo}
        
        # Build client version string
        If ($ccmBuildNoHandler) {
            $clientVersionString = $clientVersion + " (ConfigMgr " + $ccmBuildNoHandler.Value + ")"
        }
        Else {
            $clientVersionString = $clientVersion
        }

        Return $clientVersionString
    }
    Catch {
        Return 'n/a'
    }
}

Function Write-MenuHeader {
    Clear-Host
    Write-Output '###############################################'
    Write-Output '#                                             #'
    Write-Output '#          ConfigMgr LogFile Opener           #'
    Write-Output '#                    1.2.0                    #'
    Write-Output '#               msitproblog.com               #'
    Write-Output '#                                             #'
    Write-Output '###############################################'
    Write-Output ''
}

Function Invoke-MainMenu ([switch] $ResetHostname, [switch] $FirstLaunch) {
    # Reset Hostname if needed
    If ($resetHostname) {
        $hostname = ''
    }

    If ($hostname -eq '') {
        # Get targeted Computer
        Write-MenuHeader
        $hostname = Read-Host -Prompt 'Enter name of Device'

        # Assign local hostname if no hostname was specified
        If ($hostname -eq '') {
            $hostname = $env:COMPUTERNAME

            # Notify user about the assignment of the local hostname
            Invoke-MessageBox -Message "The local device name '$hostname' has been assigned." -Icon 'Info'
        }
    }

    # Perform the following checks / tasks only if the hostname was changed or on first launch
    If ($resetHostname -or $firstLaunch) {
        If ([System.Uri]::CheckHostName($hostname) -eq 'Unknown') {
            Invoke-MessageBox -Message "The specified Device name '$hostname' is not valid."
            Invoke-MainMenu -ResetHostname
        }

        # Check if host is online
        If (!(Test-Path -Path "\\$hostname\C$")) {
            Invoke-MessageBox -Message "The specified Device '$hostname' is not accessible."
            Invoke-MainMenu -ResetHostname
        }

        # Check if the specified host is the local device
        If ($hostname.Split('.')[0] -eq $env:COMPUTERNAME) {
            $hostnameIsRemote = $false
        }

        # Generate Client Version String
        $clientVersionString = Get-ClientVersionString
    }

    # Write main Menu
    Write-MenuHeader
    Write-Output "Connected Device: $hostname" 
    Write-Output "Client Version:   $clientVersionString"
    Write-Output ''
    Write-Output '------------------- CMTrace -------------------'
    Write-Output '[1] ccmsetup.log'
    Write-Output '[2] ScanAgent.log, Updates*.log, WUAHandler.log'
    Write-Output '[3] AppDiscovery.log'
    Write-Output '[4] AppEnforce.log'
    Write-Output '[5] execmgr.log'
    Write-Output '[6] CcmExec.log'
    Write-Output '[7] ClientIDManagerStartup.log'
    Write-Output '[8] Policy*.log, StatusAgent.log'
    Write-Output '[9] EndpointProtectionAgent.log'
    Write-Output '[10] CAS.log, CIDownloader.log, DataTransferService.log'
    Write-Output '[11] CcmEval.log'
    Write-Output '[12] InventoryAgent.log, InventoryProvider.log'
    Write-Output '[13] smsts.log'
    Write-Output '[14] StateMessage.log'
    Write-Output '[15] WindowsUpdate.log'
    Write-Output ''
    Write-Output '---------------- File Explorer ----------------'
    Write-Output '[50] C:\Windows\CCM\Logs'
    Write-Output '[51] C:\Windows\ccmcache'
    Write-Output '[52] C:\Windows\ccmsetup'
    Write-Output '[53] C:\Windows\Logs\Software'
    Write-Output ''
    Write-Output '-------------------- Tool ---------------------'
    Write-Output '[96] Client Actions'
    Write-Output '[97] Start CMTrace'
    Write-Output '[98] Change Device'
    Write-Output '[99] Exit'
    Write-Output ''

    Switch (Read-Host -Prompt 'Please select an Action') {
        1 {Open-LogFile -Action 'ccmsetup'}
        2 {Open-LogFile -Action 'ccmupdate'}
        3 {Open-LogFile -Action 'ccmappdiscovery'}
        4 {Open-LogFile -Action 'ccmappenforce'}
        5 {Open-LogFile -Action 'ccmexecmgr'}
        6 {Open-LogFile -Action 'ccmexec'}
        7 {Open-LogFile -Action 'ccmstartup'}
        8 {Open-LogFile -Action 'ccmpolicy'}
        9 {Open-LogFile -Action 'ccmepagent'}
        10 {Open-LogFile -Action 'ccmdownload'}
        11 {Open-LogFile -Action 'ccmeval'}
        12 {Open-LogFile -Action 'ccminventory'}
        13 {Open-LogFile -Action 'ccmsmsts'}
        14 {Open-LogFile -Action 'ccmstatemessage'}
        15 {Open-LogFile -Action 'winupdate'}
        50 {Open-Path -Path 'C$\Windows\CCM\Logs'}
        51 {Open-Path -Path 'C$\Windows\ccmcache'}
        52 {Open-Path -Path 'C$\Windows\ccmsetup'}
        53 {Open-Path -Path 'C$\Windows\Logs\Software'}
        96 {Invoke-ClientActionMenu}
        97 {Invoke-CMTrace}
        98 {Invoke-MainMenu -ResetHostname}
        99 {Clear-Host; Exit}
        Default {Invoke-MainMenu}
    }
}

Function Invoke-ClientActionMenu {
    Write-MenuHeader
    Write-Output "Connected Device: $hostname"
    Write-Output "Client Version:   $clientVersionString"
    Write-Output ''
    Write-Output '--------------- Client Actions ----------------'
    Write-Output '[1] Application Deployment Evaluation Cycle'
    Write-Output '[2] Discovery Data Collection Cycle'
    Write-Output '[3] File Collection Cycle'
    Write-Output '[4] Hardware Inventory Cycle'
    Write-Output '[5] Machine Policy Retrieval & Evaluation Cycle'
    Write-Output '[6] Software Inventory Cycle'
    Write-Output '[7] Software Metering Usage Report Cycle'
    Write-Output '[8] Software Updates Assignments Evaluation Cycle'
    Write-Output '[9] Software Update Scan Cycle'
    Write-Output '[10] Windows Installers Source List Update Cycle'
    Write-Output '[11] State Message Refresh'
    Write-Output '[12] Reevaluate Endpoint deployment '
    Write-Output '[13] Reevaluate Endpoint AM policy '
    Write-Output ''
    Write-Output '-------------------- Tool ---------------------'
    Write-Output '[98] Back to Main Menu'
    Write-Output '[99] Exit'
    Write-Output ''

    Switch (Read-Host -Prompt 'Please select an Action') {
        1 {Invoke-ClientAction -Action '00000000-0000-0000-0000-000000000121'}
        2 {Invoke-ClientAction -Action '00000000-0000-0000-0000-000000000003'}
        3 {Invoke-ClientAction -Action '00000000-0000-0000-0000-000000000010'}
        4 {Invoke-ClientAction -Action '00000000-0000-0000-0000-000000000001'}
        5 {Invoke-ClientAction -Action '00000000-0000-0000-0000-000000000021','00000000-0000-0000-0000-000000000022'}
        6 {Invoke-ClientAction -Action '00000000-0000-0000-0000-000000000002'}
        7 {Invoke-ClientAction -Action '00000000-0000-0000-0000-000000000031'}
        8 {Invoke-ClientAction -Action '00000000-0000-0000-0000-000000000108'}
        9 {Invoke-ClientAction -Action '00000000-0000-0000-0000-000000000113'}
        10 {Invoke-ClientAction -Action '00000000-0000-0000-0000-000000000032'}
        11 {Invoke-ClientAction -Action '00000000-0000-0000-0000-000000000111'}
        12 {Invoke-ClientAction -Action '00000000-0000-0000-0000-000000000221'}
        13 {Invoke-ClientAction -Action '00000000-0000-0000-0000-000000000222'}
        98 {Invoke-MainMenu}
        99 {Clear-Host; Exit}
        Default {Invoke-ClientActionMenu}
    }
}

# Check PowerShell Version
If ($PSVersionTable.PSVersion.Major -lt 3) {
    Invoke-MessageBox -Message 'This tool requires PowerShell 3.0 or later!'
    Exit
}

# Fire up Main Menu
Invoke-MainMenu -FirstLaunch