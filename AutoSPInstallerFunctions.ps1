# ===================================================================================
# EXTERNAL FUNCTIONS
# ===================================================================================

#Region Start logging to user's desktop
Function StartTracing
{
    $script:LogTime = Get-Date -Format yyyy-MM-dd_h-mm
    $script:LogFile = "$env:USERPROFILE\Desktop\AutoSPInstaller-$LogTime.rtf"
    Start-Transcript -Path $LogFile -Force
    
    $script:StartDate = Get-Date
    Write-Host -ForegroundColor White "-----------------------------------"
    Write-Host -ForegroundColor White "| Automated SP2010 install script |"
    Write-Host -ForegroundColor White "| Started on: $StartDate |"
    Write-Host -ForegroundColor White "-----------------------------------"
}
#EndRegion

#Region Check Configuration File 
Function CheckConfig
{
    # Check that the config file exists.
    if (-not $(Test-Path -Path $InputFile -Type Leaf))
    {
    	Write-Error -message (" - Configuration file '" + $InputFile + "' does not exist.")
    }
}
#EndRegion

#Region Check Installation Account
# ===================================================================================
# Func: CheckInstallAccount
# Desc: Check the install account and 
# ===================================================================================
Function CheckInstallAccount([xml]$xmlinput)
{
    # Check if we are running under Farm Account credentials
    If ($env:USERDOMAIN+"\"+$env:USERNAME -eq $FarmAcct) 
    {
        Write-Host  -ForegroundColor Yellow " - WARNING: Running install using Farm Account: $FarmAcct"
    }
}
#EndRegion

#Region Disable Loopback Check and Services
# ===================================================================================
# Func: DisableLoopbackCheck
# Desc: Disable Loopback Check
# ===================================================================================
Function DisableLoopbackCheck([xml]$xmlinput)
{
    # Disable the Loopback Check on stand alone demo servers.  
    # This setting usually kicks out a 401 error when you try to navigate to sites that resolve to a loopback address e.g.  127.0.0.1 
    if ($xmlinput.Configuration.Install.Disable.Loopback -eq $true)
    {
    	WriteLine
        Write-Host -ForegroundColor White " - Disabling Loopback Check"

        $LsaPath = "HKLM:\System\CurrentControlSet\Control\Lsa"
        $LsaPathValue = Get-ItemProperty -path $LsaPath
        If (-not ($LsaPathValue.DisableLoopbackCheck -eq "1"))
        {
            New-ItemProperty HKLM:\System\CurrentControlSet\Control\Lsa -Name "DisableLoopbackCheck" -value "1" -PropertyType dword -Force | Out-Null
        }
    	WriteLine    
    }
}

# ===================================================================================
# Func: DisableServices
# Desc: Disable Unused Services or set status to Manual
# ===================================================================================
Function DisableServices([xml]$xmlinput)
{        
    if ($xmlinput.Configuration.Install.Disable.UnusedServices -eq $true)
    {
    	WriteLine
        Write-Host -ForegroundColor White " - Setting services Spooler, AudioSrv and TabletInputService to Manual..."

        $ServicesToSetManual = "Spooler","AudioSrv","TabletInputService"
        ForEach ($SvcName in $ServicesToSetManual)
        {
            $Svc = get-wmiobject win32_service | where-object {$_.Name -eq $SvcName} 
            $SvcStartMode = $Svc.StartMode
            $SvcState = $Svc.State
            If (($SvcState -eq "Running") -and ($SvcStartMode -eq "Auto"))
            {
                Stop-Service -Name $SvcName
                Set-Service -name $SvcName -startupType Manual
                Write-Host -ForegroundColor White " - Service $SvcName is now set to Manual start"
            }
            Else 
            {
                Write-Host -ForegroundColor White " - $SvcName is already stopped and set Manual, no action required."
            }
        }
    	
        Write-Host -ForegroundColor White " - Setting unused services WerSvc to Disabled..."
        $ServicesToDisable = "WerSvc"
        ForEach ($SvcName in $ServicesToDisable) 
        {
            $Svc = get-wmiobject win32_service | where-object {$_.Name -eq $SvcName} 
            $SvcStartMode = $Svc.StartMode
            $SvcState = $Svc.State
            If (($SvcState -eq "Running") -and (($SvcStartMode -eq "Auto") -or ($SvcStartMode -eq "Manual")))
            {
                Stop-Service -Name $SvcName
                Set-Service -name $SvcName -startupType Disabled
                Write-Host -ForegroundColor White " - Service $SvcName is now stopped and disabled."
            }
            Else 
            {
                Write-Host -ForegroundColor White " - $SvcName is already stopped and disabled, no action required."
            }
        }
        Write-Host -ForegroundColor White " - Finished disabling services."
        WriteLine
    }
    
}
#EndRegion

#Region Install Prerequisites
# ===================================================================================
# Func: Install Prerequisites
# Desc: If SharePoint is not already installed install the Prerequisites
# ===================================================================================
Function InstallPrerequisites([xml]$xmlinput)
{
    WriteLine
    If (Test-Path "$env:CommonProgramFiles\Microsoft Shared\Web Server Extensions\14\BIN\stsadm.exe") #Crude way of checking if SP2010 is already installed
    {
    	Write-Host -ForegroundColor White " - SP2010 prerequisites appear be already installed - skipping install."
    }
    Else
    {
    	Write-Host -ForegroundColor White " - Installing Prerequisite Software:"
    	Write-Host -ForegroundColor White " - Running Prerequisite Installer..."

    	Try 
    	{
			If ($xmlinput.Configuration.Install.OfflineInstall -eq $true) # Install all prerequisites from local folder
    		{
    			Start-Process "$bits\PrerequisiteInstaller.exe" -Wait -ArgumentList "/unattended `
    																				/SQLNCli:`"$bits\PrerequisiteInstallerFiles\sqlncli.msi`" `
    																				/ChartControl:`"$bits\PrerequisiteInstallerFiles\MSChart.exe`" `
    																				/NETFX35SP1:`"$bits\PrerequisiteInstallerFiles\dotnetfx35.exe`" `
    																				/PowerShell:`"$bits\PrerequisiteInstallerFiles\Windows6.0-KB968930-x64.msu`" `
    																				/KB976394:`"$bits\PrerequisiteInstallerFiles\Windows6.0-KB976394-x64.msu`" `
    																				/KB976462:`"$bits\PrerequisiteInstallerFiles\Windows6.1-KB976462-v2-x64.msu`" `
    																				/IDFX:`"$bits\PrerequisiteInstallerFiles\Windows6.0-KB974405-x64.msu`" `
    																				/IDFXR2:`"$bits\PrerequisiteInstallerFiles\Windows6.1-KB974405-x64.msu`" `
    																				/Sync:`"$bits\PrerequisiteInstallerFiles\Synchronization.msi`" `
    																				/FilterPack:`"$bits\PrerequisiteInstallerFiles\FilterPack\FilterPack.msi`" `
    																				/ADOMD:`"$bits\PrerequisiteInstallerFiles\SQLSERVER2008_ASADOMD10.msi`" `
    																				/ReportingServices:`"$bits\PrerequisiteInstallerFiles\rsSharePoint.msi`" `
    																				/Speech:`"$bits\PrerequisiteInstallerFiles\SpeechPlatformRuntime.msi`" `
    																				/SpeechLPK:`"$bits\PrerequisiteInstallerFiles\MSSpeech_SR_en-US_TELE.msi`""																		
    			If (-not $?) {throw}
    		}
    		Else # Regular prerequisite install - download required files
    		{
    			Start-Process "$bits\PrerequisiteInstaller.exe" -Wait -ArgumentList "/unattended" -WindowStyle Minimized
    			If (-not $?) {throw}
    		}
    	}
    	Catch 
    	{
    		Write-Host -ForegroundColor Red " - Error: $LastExitCode"
    		If ($LastExitCode -eq "1") {throw " - Another instance of this application is already running"}
    		ElseIf ($LastExitCode -eq "2") {throw " - Invalid command line parameter(s)"}
    		ElseIf ($LastExitCode -eq "1001") {throw " - A pending restart blocks installation"}
    		ElseIf ($LastExitCode -eq "3010") {throw " - A restart is needed"}
    		Else {throw " - An unknown error occurred installing prerequisites"}
    	}
    	# Parsing most recent PreRequisiteInstaller log for errors or restart requirements, since $LastExitCode doesn't seem to work...
    	$PreReqLog = get-childitem $env:TEMP | ? {$_.Name -like "PrerequisiteInstaller.*"} | Sort-Object -Descending -Property "LastWriteTime" | Select-Object -first 1
    	If ($PreReqLog -eq $null) 
    	{
    		Write-Warning " - Could not find PrerequisiteInstaller log file"
    	}
    	Else 
    	{
    		# Get error(s) from log
    		$PreReqLastError = $PreReqLog | select-string -SimpleMatch -Pattern "Error" -Encoding Unicode | ? {$_.Line  -notlike "*Startup task*"}
    		If ($PreReqLastError)
    		{
    			Write-Warning $PreReqLastError.Line
    			$PreReqLastReturncode = $PreReqLog | select-string -SimpleMatch -Pattern "Last return code" -Encoding Unicode | Select-Object -Last 1
    			If ($PreReqLastReturnCode) {Write-Warning $PreReqLastReturncode.Line}
    			Write-Host -ForegroundColor White " - Review the log file and try to correct any error conditions."
    			Pause
    			Invoke-Item $env:TEMP\$PreReqLog
    			break
    		}
    		# Look for restart requirement in log
    		$PreReqRestartNeeded = $PreReqLog | select-string -SimpleMatch -Pattern "0XBC2=3010" -Encoding Unicode
    		If ($PreReqRestartNeeded)
    		{
    			Write-Warning " - One or more of the prerequisites requires a restart."
    			Write-Host -ForegroundColor White " - Run the script again after restarting to continue."
    			Pause
    			break
    		}
    	}
        
    	Write-Host -ForegroundColor White " - All Prerequisite Software installed successfully."	
    }
	WriteLine
}
#EndRegion

#Region Install SharePoint
# ===================================================================================
# Func: InstallSharePoint
# Desc: Installs the SharePoint binaries in unattended mode
# ===================================================================================
Function InstallSharePoint([xml]$xmlinput)
{
    WriteLine
	If  (Test-Path "$env:CommonProgramFiles\Microsoft Shared\Web Server Extensions\14\BIN\stsadm.exe") #Crude way of checking if SP2010 is already installed
    {
    	Write-Host -ForegroundColor White " - SP2010 binaries appear to be already installed - skipping installation."
    }
    Else
    {
    	# Install SharePoint Binaries
        $config = $dp0 + "\" + $xmlinput.Configuration.Install.ConfigFile
    	If (Test-Path "$bits\setup.exe")
    	{
    		Write-Host -ForegroundColor White " - Installing SharePoint binaries..."
      		try
    		{
    			Start-Process "$bits\setup.exe" -ArgumentList "/config `"$config`"" -WindowStyle Minimized -Wait
    			If (-not $?) {throw}
    		}
    		catch 
    		{
    			Write-Warning " - Error $LastExitCode occurred running $bits\setup.exe"
    			break
    		}
    		
    		# Parsing most recent SharePoint Server Setup log for errors or restart requirements, since $LastExitCode doesn't seem to work...
    		$SetupLog = get-childitem $env:TEMP | ? {$_.Name -like "SharePoint Server Setup*"} | Sort-Object -Descending -Property "LastWriteTime" | Select-Object -first 1
    		If ($SetupLog -eq $null) 
    		{
    			Write-Warning " - Could not find SharePoint Server Setup log file!"
    			Pause
    			break
    		}
    		Else 
    		{
    			# Get error(s) from log
    			$SetupLastError = $SetupLog | select-string -SimpleMatch -Pattern "Error:" | Select-Object -Last 1 #| ? {$_.Line  -notlike "*Startup task*"}
    			If ($SetupLastError)
    			{
    				Write-Warning $SetupLastError.Line
    				Write-Host -ForegroundColor White " - Review the log file and try to correct any error conditions."
    				Pause
    				Invoke-Item $env:TEMP\$SetupLog
    				break
    			}
    			# Look for restart requirement in log
    			$SetupRestartNotNeeded = $SetupLog | select-string -SimpleMatch -Pattern "System reboot is not pending."
    			If (!($SetupRestartNotNeeded))
    			{
    				Write-Host -ForegroundColor White " - SharePoint setup requires a restart."
    				Write-Host -ForegroundColor White " - Run the script again after restarting to continue."
    				Pause
    				break
    			}
    		}
    		Write-Host -ForegroundColor Blue " - Waiting for SharePoint Products and Technologies Wizard to launch..." -NoNewline
    		While ((Get-Process |?{$_.ProcessName -like "psconfigui*"}) -eq $null)
    		{
    			Write-Host -ForegroundColor Blue "." -NoNewline
    			sleep 1
    		}
    		Write-Host -ForegroundColor Blue "Done."
      		Write-Host -ForegroundColor White " - Exiting Products and Technologies Wizard - using Powershell instead!"
    		Stop-Process -Name psconfigui
    	}
    	Else
    	{
    	  	Write-Host -ForegroundColor Red " - Install path $bits not found!!"
    	  	Pause
    		break
    	}
    }
	WriteLine
}
#EndRegion

#Region Install Office Web Apps
# ===================================================================================
# Func: InstallOfficeWebApps
# Desc: Installs the OWA binaries in unattended mode
# From: Ported over by user http://www.codeplex.com/site/users/view/cygoh originally from the InstallSharePoint function, fixed up by brianlala
# Originally posted on: http://autospinstaller.codeplex.com/discussions/233530
# ===================================================================================
Function InstallOfficeWebApps([xml]$xmlinput)
{
	If ($xmlinput.Configuration.OfficeWebApps.Install -eq $true)
	{
		WriteLine
		If (Test-Path "$env:CommonProgramFiles\Microsoft Shared\Web Server Extensions\14\TEMPLATE\FEATURES\OfficeWebApps\feature.xml") # Crude way of checking if Office Web Apps is already installed
		{
			Write-Host -ForegroundColor White " - Office Web Apps binaries appear to be already installed - skipping install."
		}
		Else
		{
			# Install Office Web Apps Binaries
	        $config = $dp0 + "\" + $xmlinput.Configuration.OfficeWebApps.ConfigFile
			If (Test-Path "$bits\OfficeWebApps\setup.exe")
			{
				Write-Host -ForegroundColor White " - Installing Office Web Apps binaries..."
				try
				{
					Start-Process "$bits\OfficeWebApps\setup.exe" -ArgumentList "/config `"$config`"" -WindowStyle Minimized -Wait
					If (-not $?) {throw}
				}
				catch 
				{
					Write-Warning " - Error $LastExitCode occurred running $bitslocation\OfficeWebApps\setup.exe"
					break
				}
				# Parsing most recent Office Web Apps Setup log for errors or restart requirements, since $LastExitCode doesn't seem to work...
				$SetupLog = get-childitem $env:TEMP | ? {$_.Name -like "Wac Server Setup*"} | Sort-Object -Descending -Property "LastWriteTime" | Select-Object -first 1
				If ($SetupLog -eq $null) 
				{
					Write-Warning " - Could not find Office Web Apps Setup log file!"
					Pause
					break
				}
				Else 
				{
					# Get error(s) from log
					$SetupLastError = $SetupLog | select-string -SimpleMatch -Pattern "Error:" | Select-Object -Last 1 #| ? {$_.Line -notlike "*Startup task*"}
					If ($SetupLastError)
					{
						Write-Warning $SetupLastError.Line
						Write-Host -ForegroundColor White " - Review the log file and try to correct any error conditions."
						Pause
						Invoke-Item $env:TEMP\$SetupLog
						break
					}
					# Look for restart requirement in log
					$SetupRestartNotNeeded = $SetupLog | select-string -SimpleMatch -Pattern "System reboot is not pending."
					If (!($SetupRestartNotNeeded))
					{
						Write-Host -ForegroundColor White " - SharePoint setup requires a restart."
						Write-Host -ForegroundColor White " - Run the script again after restarting to continue."
						Pause
						break
					}
				}
				Write-Host -ForegroundColor Blue " - Waiting for SharePoint Products and Technologies Wizard to launch..." -NoNewline
				While ((Get-Process |?{$_.ProcessName -like "psconfigui*"}) -eq $null)
				{
					Write-Host -ForegroundColor Blue "." -NoNewline
					sleep 1
				}
				# The Connect-SPConfigurationDatabase cmdlet throws an error about an "upgrade required" if we don't at least *launch* the Wizard, so we wait to let it launch, then kill it.
				Start-Sleep 10
				Write-Host -ForegroundColor Blue "Done."
				Write-Host -ForegroundColor White " - Exiting Products and Technologies Wizard - using Powershell instead!"
				Stop-Process -Name psconfigui
			}
			Else
			{
				Write-Host -ForegroundColor Red " - Install path $bits\OfficeWebApps not found!!"
				Pause
				break
			}
		}
		WriteLine
	}
}
#EndRegion

#Region Configure Office Web Apps
Function ConfigureOfficeWebApps([xml]$xmlinput)
{
	If ($xmlinput.Configuration.OfficeWebApps.Install -eq $true)
	{
		Writeline
		<#Start-Process -FilePath $PSConfig -ArgumentList "-cmd upgrade -inplace b2b -wait -force -cmd installcheck -noinstallcheck" -NoNewWindow -Wait -ErrorAction SilentlyContinue | Out-Null
		$PSConfigLog = get-childitem "$env:CommonProgramFiles\Microsoft Shared\Web Server Extensions\14\LOGS" | ? {$_.Name -like "PSCDiagnostics*"} | Sort-Object -Descending -Property "LastWriteTime" | Select-Object -first 1
		If ($PSConfigLog -eq $null) 
		{
			Write-Warning " - Could not find PSConfig log file!"
			Pause
			break
		}
		Else 
		{
			# Get error(s) from log
			##$PSConfigLastError = $PSConfigLog | select-string -SimpleMatch -CaseSensitive -Pattern "ERR" | Select-Object -Last 1
			If ($PSConfigLastError)
			{
				Write-Warning $PSConfigLastError.Line
				Write-Host -ForegroundColor White " - An error occurred configuring Office Web Apps, trying again..."
				ConfigureOfficeWebApps ($xmlinput)
			}
		}#>
		Try
		{
			Write-Host -ForegroundColor White " - Configuring Office Web Apps..."
			# Install Help Files
			Write-Host -ForegroundColor White " - Installing Help Collection..."
			Install-SPHelpCollection -All
			# Install application content 
			Write-Host -ForegroundColor White " - Installing Application Content..."
			Install-SPApplicationContent
			# Secure resources
			Write-Host -ForegroundColor White " - Securing Resources..."
			Initialize-SPResourceSecurity
			# Install Services
			Write-Host -ForegroundColor White " - Installing Services..."
			Install-SPService
			If (!$?) {Throw}
			# Install (all) features
			Write-Host -ForegroundColor White " - Installing Features..."
		    $Features = Install-SPFeature –AllExistingFeatures -Force
		}
		Catch	
		{
			Write-Output $_
			Pause
			Break
		}
		Writeline
	}
}
#EndRegion

#Region Install Language Packs
# ===================================================================================
# Func: Install Language Packs
# Desc: Install language packs and report on any languages installed
# ===================================================================================
Function InstallLanguagePacks([xml]$xmlinput)
{
	WriteLine
    #Look for Server language packs
    $ServerLanguagePacks = (Get-ChildItem "$bits\LanguagePacks" -Name -Include ServerLanguagePack*.exe -ErrorAction SilentlyContinue)
    If ($ServerLanguagePacks)
    {
    	Write-Host -ForegroundColor White " - Installing SharePoint (Server) Language Packs:"
    	#Get installed languages from registry (HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Office Server\14.0\InstalledLanguages)
        $InstalledOfficeServerLanguages = (Get-Item "HKLM:\Software\Microsoft\Office Server\14.0\InstalledLanguages").GetValueNames() | ? {$_ -ne ""}
    <#
    	#Another way to get installed languages, thanks to Anders Rask (@AndersRask)!
    	##$InstalledOfficeServerLanguages = [Microsoft.SharePoint.SPRegionalSettings]::GlobalInstalledLanguages
    #>
    	ForEach ($LanguagePack in $ServerLanguagePacks)
    	{
            #Slightly convoluted check to see if language pack is already installed, based on name of language pack file.
            # This only works if you've renamed your language pack(s) to follow the convention "ServerLanguagePack_XX-XX.exe" where <XX-XX> is a culture such as <en-us>.
    		$Language = $InstalledOfficeServerLanguages | ? {$_ -eq (($LanguagePack -replace "ServerLanguagePack_","") -replace ".exe","")}
            If (!$Language)
            {
    	        Write-Host -ForegroundColor Blue " - Installing $LanguagePack..." -NoNewline
    	        Start-Process -FilePath "$bits\LanguagePacks\$LanguagePack" -ArgumentList "/quiet /norestart"
    	        While (Get-Process -Name ($LanguagePack -replace ".exe", "") -ErrorAction SilentlyContinue)
    	        {
    	        	Write-Host -ForegroundColor Blue "." -NoNewline
    	        	sleep 5
    	        }
       		    Write-Host -BackgroundColor Blue -ForegroundColor Black "Done."
            }
            Else
            {
                Write-Host -ForegroundColor White " - Language $Language already appears to be installed, skipping."
            }
    	}
    	Write-Host -ForegroundColor White " - Language Pack installation complete."
    }
    Else 
    {
        Write-Host -ForegroundColor White " - No language packs found in $bits\LanguagePacks, skipping."
    }

    # Get and note installed languages
    $InstalledOfficeServerLanguages = (Get-Item "HKLM:\Software\Microsoft\Office Server\14.0\InstalledLanguages").GetValueNames() | ? {$_ -ne ""}
    Write-Host -ForegroundColor White " - Currently installed languages:" 
    ForEach ($Language in $InstalledOfficeServerLanguages)
    {
    	Write-Host "  -" ([System.Globalization.CultureInfo]::GetCultureInfo($Language).DisplayName)
    }
	WriteLine
}
#EndRegion

#Region Configure Farm Account
# ===================================================================================
# Func: ConfigureFarmAdmin
# Desc: Sets up the farm account and adds to Local admins if needed
# ===================================================================================
Function ConfigureFarmAdmin([xml]$xmlinput)
{        
	If (($xmlinput.Configuration.Farm.Account.getAttribute("AddToLocalAdminsDuringSetup") -eq $true) -and ($xmlinput.Configuration.ServiceApps.UserProfileServiceApp.Provision -eq $true))
    {
        WriteLine
		#Add to Admins Group
        $FarmAcct = $xmlinput.Configuration.Farm.Account.Username
        Write-Host -ForegroundColor White " - Adding $FarmAcct to local Administrators (only for install)..."
        $FarmAcctDomain,$FarmAcctUser = $FarmAcct -Split "\\"
        try
    	{
    		([ADSI]"WinNT://$env:COMPUTERNAME/Administrators,group").Add("WinNT://$FarmAcctDomain/$FarmAcctUser")
            If (-not $?) {throw}
			# Restart the SPTimerV4 service if it's running, so it will pick up the new credential
			If ((Get-Service -Name SPTimerV4).Status -eq "Running")
			{
				Write-Host -ForegroundColor White " - Restarting SharePoint Timer Service..."
				Restart-Service SPTimerV4
			}
    	}
        catch {Write-host -ForegroundColor White " - $FarmAcct is already an Administrator." }
		WriteLine
    }
}

# ===================================================================================
# Func: GetFarmCredentials
# Desc: Return the credentials for the farm account, prompt the user if need more info
# ===================================================================================
Function GetFarmCredentials([xml]$xmlinput)
{        
    $FarmAcct = $xmlinput.Configuration.Farm.Account.Username
    $FarmAcctPWD = $xmlinput.Configuration.Farm.Account.Password
    If (!($FarmAcct) -or $FarmAcct -eq "" -or !($FarmAcctPWD) -or $FarmAcctPWD -eq "") 
    {
        Write-Host -BackgroundColor Gray -ForegroundColor DarkBlue " - Prompting for Farm Account:"
    	$farmCredential = $host.ui.PromptForCredential("Farm Setup", "Enter Farm Account Credentials:", "$FarmAcct", "NetBiosUserName" )
    } 
    else
    {
        $secPassword = ConvertTo-SecureString "$FarmAcctPWD" –AsPlaintext –Force 
        $farmCredential = New-Object System.Management.Automation.PsCredential $FarmAcct,$secPassword
    }
    return $farmCredential
}
#EndRegion

#Region Get Farm Passphrase
Function GetFarmPassphrase([xml]$xmlinput)
{
	$script:FarmPassphrase = $xmlinput.Configuration.Farm.Passphrase
	If (!($FarmPassphrase) -or ($FarmPassphrase -eq ""))
	{
		$script:FarmPassphrase = Read-Host -Prompt " - Please enter the farm passphrase now" -AsSecureString
		If (!($FarmPassphrase) -or ($FarmPassphrase -eq "")) {Write-Warning " - Farm passphrase is required!" ; Pause; break}
    }
	Return $FarmPassphrase
}
#EndRegion

#Region Get Secure Farm Passphrase
# ===================================================================================
# Func: GetSecureFarmPassphrase
# Desc: Return the Farm Phrase as a secure string
# ===================================================================================
Function GetSecureFarmPassphrase([xml]$xmlinput)
{        
    If (!($FarmPassphrase) -or ($FarmPassphrase -eq ""))
    {
    	$FarmPassphrase = GetFarmPassPhrase ($xmlinput)
	}
	If ($FarmPassPhrase.GetType().Name -ne "SecureString")
	{
		$SecPhrase = ConvertTo-SecureString $FarmPassphrase –AsPlaintext –Force
	}
	Else {$SecPhrase = $FarmPassphrase}
 	Return $SecPhrase
}
#EndRegion

#Region Update Service Process Identity

# ====================================================================================
# Func: UpdateProcessIdentity
# Desc: Updates the account a specified service runs under to the general app pool account
# ====================================================================================
Function UpdateProcessIdentity ($ServiceToUpdate)
{
	$spservice = Get-spserviceaccountxml $xmlinput
	# Managed Account
   	$ManagedAccountGen = Get-SPManagedAccount | Where-Object {$_.UserName -eq $($spservice.username)}
   	if ($ManagedAccountGen -eq $NULL) { throw " - Managed Account $($spservice.username) not found" }
	Write-Host -ForegroundColor White " - Updating $($ServiceToUpdate.TypeName) to run as $($ManagedAccountGen.UserName)..."
	# Set the Process Identity to our general App Pool Account; otherwise it's set by default to the Farm Account and gives warnings in the Health Analyzer
	$ServiceToUpdate.Service.ProcessIdentity.CurrentIdentityType = "SpecificUser"
	$ServiceToUpdate.Service.ProcessIdentity.ManagedAccount = $ManagedAccountGen
	$ServiceToUpdate.Service.ProcessIdentity.Update()
	$ServiceToUpdate.Service.ProcessIdentity.Deploy()
	$ServiceToUpdate.Update()
}
#EndRegion

#Region Create or Join Farm
# ===================================================================================
# Func: CreateOrJoinFarm
# Desc: Check if the farm is created 
# ===================================================================================
Function CreateOrJoinFarm([xml]$xmlinput, $SecPhrase, $farmCredential)
{
    WriteLine
	Start-SPAssignment -Global | Out-Null

    $script:DBPrefix = $xmlinput.Configuration.Farm.Database.DBPrefix
	If (($DBPrefix -ne "") -and ($DBPrefix -ne $null)) {$script:DBPrefix += "_"}
	If ($DBPrefix -like "*localhost*") {$script:DBPrefix = $DBPrefix -replace "localhost","$env:COMPUTERNAME"}
    $script:ConfigDB = $DBPrefix+$xmlinput.Configuration.Farm.Database.ConfigDB
    
    # Look for an existing farm and join the farm if not already joined, or create a new farm
    try
    {
    	Write-Host -ForegroundColor White " - Checking farm membership for $env:COMPUTERNAME in `"$configDB`"..."
    	$SPFarm = Get-SPFarm | Where-Object {$_.Name -eq $configDB} -ErrorAction SilentlyContinue
    }
    catch {""}
    If ($SPFarm -eq $null)
    {
    	try
    	{
            $DBServer =  $xmlinput.Configuration.Farm.Database.DBServer
            $CentralAdminContentDB = $DBPrefix+$xmlinput.Configuration.Farm.CentralAdmin.Database
            
    		Write-Host -ForegroundColor White " - Attempting to join farm on `"$ConfigDB`"..."
    		$connectFarm = Connect-SPConfigurationDatabase -DatabaseName "$configDB" -Passphrase $SecPhrase -DatabaseServer "$DBServer" -ErrorAction SilentlyContinue
    		If (-not $?)
    		{
    			Write-Host -ForegroundColor White " - No existing farm found.`n - Creating config database `"$configDB`"..."
    			# Waiting a few seconds seems to help with the Connect-SPConfigurationDatabase barging in on the New-SPConfigurationDatabase command; not sure why...
    			sleep 5
				New-SPConfigurationDatabase –DatabaseName "$configDB" –DatabaseServer "$DBServer" –AdministrationContentDatabaseName "$CentralAdminContentDB" –Passphrase $SecPhrase –FarmCredentials $farmCredential
    			If (-not $?) {throw}
    			Else {$FarmMessage = " - Done creating configuration database for farm."}
    		}
    		Else 
            {
                $FarmMessage = " - Done joining farm."
				[bool]$script:FarmExists = $true

            }
    	}
    	catch 
    	{
    		Write-Output $_
    		Pause
    		break
    	}
    }
    Else 
    {
       	[bool]$script:FarmExists = $true
		$FarmMessage = " - $env:COMPUTERNAME is already joined to farm on `"$ConfigDB`"."
    }
    
    Write-Host -ForegroundColor White $FarmMessage
	WriteLine
}
#EndRegion

#Region Configure Farm
# ===================================================================================
# Func: CreateCentralAdmin
# Desc: Setup Central Admin Web Site, Check the topology of an existing farm, and configure the farm as required.
# ===================================================================================
Function CreateCentralAdmin([xml]$xmlinput)
{
	If ($($xmlinput.Configuration.Farm.CentralAdmin.Provision) -eq $true)
	{
		try
		{
			$CentralAdminPort =  $xmlinput.Configuration.Farm.CentralAdmin.Port
			# Check if there is already a Central Admin provisioned in the farm (by querying web apps by port); if not, create one
			If (!(Get-SPWebApplication -IncludeCentralAdministration | ? {$_.Url -like "*:$CentralAdminPort*"}))
			{
				# Create Central Admin for farm
				Write-Host -ForegroundColor White " - Creating Central Admin site..."
				$NewCentralAdmin = New-SPCentralAdministration -Port $CentralAdminPort -WindowsAuthProvider "NTLM" -ErrorVariable err
				If (-not $?) {throw}
				Write-Host -ForegroundColor Blue " - Waiting for Central Admin site..." -NoNewline
				$CentralAdmin = Get-SPWebApplication -IncludeCentralAdministration | ? {$_.Url -like "http://$($env:COMPUTERNAME):$CentralAdminPort*"}
				While ($CentralAdmin.Status -ne "Online") 
				{
					Write-Host -ForegroundColor Blue "." -NoNewline
					sleep 1
					$CentralAdmin = Get-SPWebApplication -IncludeCentralAdministration | ? {$_.Url -like "http://$($env:COMPUTERNAME):$CentralAdminPort*"}
				}
				Write-Host -BackgroundColor Blue -ForegroundColor Black $($CentralAdmin.Status)
			}
			Else #Create a Central Admin site locally, with an AAM to the existing Central Admin
			{
				Write-Host -ForegroundColor White " - Creating local Central Admin site..."
				$NewCentralAdmin = New-SPCentralAdministration
			}
		}
		catch	
		{
	   		If ($err -like "*update conflict*")
			{
				Write-Warning " - A concurrency error occured, trying again."
				CreateCentralAdmin ($xmlinput)
			}
			Else 
			{
				Write-Output $_
				Pause
				break
			}
		}
	}
}

# ===================================================================================
# Func: CheckFarmTopology
# Desc: Check if there is already more than one server in the farm (not including the database server)
# ===================================================================================
Function CheckFarmTopology([xml]$xmlinput)
{
	$DBServer =  $xmlinput.Configuration.Farm.Database.DBServer
	$SPFarm = Get-SPFarm | Where-Object {$_.Name -eq $ConfigDB}
	ForEach ($Srv in $SPFarm.Servers) {If (($Srv -like "*$DBServer*") -and ($DBServer -ne $env:COMPUTERNAME)) {[bool]$script:DBLocal = $false}}
	If (($($SPFarm.Servers.Count) -gt 1) -and ($DBLocal -eq $false)) {[bool]$script:FirstServer = $false}
	Else {[bool]$script:FirstServer = $true}
}

# ===================================================================================
# Func: ConfigureFarm
# Desc: Setup Central Admin Web Site, Check the topology of an existing farm, and configure the farm as required.
# ===================================================================================
Function ConfigureFarm([xml]$xmlinput)
{
	WriteLine
	Write-Host -ForegroundColor White " - Configuring the SharePoint farm/server..."
	# Force a full configuration if this is the first web/app server in the farm
	If ((!($FarmExists)) -or ($FirstServer -eq $true)) {[bool]$DoFullConfig = $true}
	try
	{
		If ($DoFullConfig)
		{
			# Install Help Files
			##$SPHelpTimer = Get-SPTimerJob | ? {$_.TypeName -eq "Microsoft.SharePoint.Help.HelpCollectionInstallerJob"} | Select-Object -Last 1
			##If (!($SPHelpTimer.Status -eq "Online")) # Install help collection if there isn't already a timer job created & running
			##{
				Write-Host -ForegroundColor White " - Installing Help Collection..."
				Install-SPHelpCollection -All
			##}
			### Wait for the SP Help Collection timer job to complete
			<#Write-Host -ForegroundColor Blue " - Waiting for Help Collection Installation timer job to complete..." -NoNewline
			While ($SPHelpTimer.Status -eq "Online")
			{
				Write-Host -ForegroundColor Blue "." -NoNewline
		  		Start-Sleep 1
		  		$SPHelpTimer = Get-SPTimerJob | ? {$_.TypeName -eq "Microsoft.SharePoint.Help.HelpCollectionInstallerJob"} | Select-Object -Last 1
			}
	    	Write-Host -BackgroundColor Blue -ForegroundColor Black "Done."
			#>
		}
		# Secure resources
		Write-Host -ForegroundColor White " - Securing Resources..."
		Initialize-SPResourceSecurity
		# Install Services
		Write-Host -ForegroundColor White " - Installing Services..."
		Install-SPService
		If ($DoFullConfig)
		{
			# Install (all) features
			Write-Host -ForegroundColor White " - Installing Features..."
			$Features = Install-SPFeature –AllExistingFeatures -Force
		}
		# Detect if Central Admin URL already exists, i.e. if Central Admin web app is already provisioned on the local computer
		$CentralAdminPort =  $xmlinput.Configuration.Farm.CentralAdmin.Port
		$CentralAdmin = Get-SPWebApplication -IncludeCentralAdministration | ? {$_.Status -eq "Online"} | ? {$_.Url -like "http://$($env:COMPUTERNAME):$CentralAdminPort*"}
		
		# Provision CentralAdmin if indicated in AutoSPInstallerInput.xml and the CA web app doesn't already exist
		If (($($xmlinput.Configuration.Farm.CentralAdmin.Provision) -eq $true) -and (!($CentralAdmin))) {CreateCentralAdmin ($xmlinput)}
		# Install application content if this is a new farm
		If ($DoFullConfig)
		{
			Write-Host -ForegroundColor White " - Installing Application Content..."
			Install-SPApplicationContent
		}
	}
	catch	
	{
	    If ($err -like "*update conflict*")
		{
			Write-Warning " - A concurrency error occured, trying again."
			CreateCentralAdmin ($xmlinput)
		}
		Else 
		{
			Write-Output $_
			Pause
			break
		}
	}
	$SPRegVersion = (Get-Item -Path 'HKLM:\SOFTWARE\Microsoft\Shared Tools\Web Server Extensions\14.0\').GetValue("Version")
	If (!($SPRegVersion))
	{
		Write-Host -ForegroundColor White " - Creating Version registry value (workaround for bug in PS-based install)"
		Write-Host -ForegroundColor White -NoNewline " - Getting version number... "
		$SPBuild = "$($(Get-SPFarm).BuildVersion.Major).0.0.$($(Get-SPFarm).BuildVersion.Build)"
		Write-Host -ForegroundColor White "$SPBuild"
		New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Shared Tools\Web Server Extensions\14.0\' -Name Version -Value $SPBuild -ErrorAction SilentlyContinue | Out-Null
	}
	# Let's make sure the SharePoint Timer Service (SPTimerV4) is running
	# Per workaround in http://www.paulgrimley.com/2010/11/side-effects-of-attaching-additional.html
	If ((Get-Service SPTimerV4).Status -eq "Stopped")
	{
		Write-Host -ForegroundColor White " - Starting $((Get-Service SPTimerV4).DisplayName) Service..."
		Start-Service SPTimerV4
		If (!$?) {Throw " - Could not start Timer service!"}
	}
	Write-Host -ForegroundColor White " - Done initial farm/server config."
	WriteLine
}

#EndRegion

#Region Configure Language Packs
Function ConfigureLanguagePacks([xml]$xmlinput)
{	
	# If there were language packs installed we need to run psconfig to configure them
    If (!($FarmPassphrase) -or ($FarmPassphrase -eq ""))
    {
    	$FarmPassphrase = GetFarmPassPhrase ($xmlinput)
	}
	# If the farm passphrase is a secure string (it would be if we prompted for input earlier), we need to convert it back to plain text for PSConfig.exe to understand it
	If ($FarmPassphrase.GetType().Name -eq "SecureString") {$FarmPassphrase = ConvertTo-PlainText $FarmPassphrase}
	$InstalledOfficeServerLanguages = (Get-Item "HKLM:\Software\Microsoft\Office Server\14.0\InstalledLanguages").GetValueNames() | ? {$_ -ne ""}
	If ($InstalledOfficeServerLanguages.Count -gt 1)
	{
		WriteLine
		Write-Host -ForegroundColor White " - Configuring language packs..."
		# Let's sleep for a while to let the farm config catch up...
		Start-Sleep 20
		# Run PSConfig.exe per http://technet.microsoft.com/en-us/library/cc262108.aspx
		Start-Process -FilePath $PSConfig -ArgumentList "-cmd upgrade -inplace v2v -passphrase `"$FarmPassphrase`" -wait -force" -NoNewWindow -Wait
   		$PSConfigLog = get-childitem "$env:CommonProgramFiles\Microsoft Shared\Web Server Extensions\14\LOGS" | ? {$_.Name -like "PSCDiagnostics*"} | Sort-Object -Descending -Property "LastWriteTime" | Select-Object -first 1
    	If ($PSConfigLog -eq $null) 
    	{
    		Write-Warning " - Could not find PSConfig log file!"
    		Pause
    		break
    	}
    	Else 
    	{
    		# Get error(s) from log
    		$PSConfigLastError = $PSConfigLog | select-string -SimpleMatch -CaseSensitive -Pattern "ERR" | Select-Object -Last 1
    		If ($PSConfigLastError)
    		{
    			Write-Warning $PSConfigLastError.Line
				Write-Host -ForegroundColor White " - An error occurred configuring language packs, trying again using GUI..."
    			##ConfigureLanguagePacks ($xmlinput)
			Start-Process -FilePath $PSConfigUI -NoNewWindow -Wait
    		}
    	}
		WriteLine
	}
}
#EndRegion

#Region Add Managed Accounts
# ===================================================================================
# FUNC: AddManagedAccounts
# DESC: Adds existing accounts to SharePoint managed accounts and creates local profiles for each
# TODO: Make this more robust, prompt for blank values etc.
# ===================================================================================
Function AddManagedAccounts([xml]$xmlinput)
{
	WriteLine
	Write-Host " - Adding Managed Accounts" -ForegroundColor White 	
	if ($xmlinput.Configuration.Farm.ManagedAccounts)
	{
		foreach ($account in $xmlinput.Configuration.Farm.ManagedAccounts.ManagedAccount)
		{
            $username = $account.username
            $password = $account.Password
            $password =  ConvertTo-SecureString "$password" –AsPlaintext –Force 
            $ManagedAccount = Get-SPManagedAccount | Where-Object {$_.UserName -eq $username}
            If ($ManagedAccount -eq $NULL) 
            { 
            	Write-Host -ForegroundColor White " - Registering managed account $username..."
                If ($username -eq $null -or $password -eq $null) 
                {
                    Write-Host -BackgroundColor Gray -ForegroundColor DarkBlue " - Prompting for Account: "
                	$credAccount = $host.ui.PromptForCredential("Managed Account", "Enter Account Credentials:", "", "NetBiosUserName" )
                } 
                else
                {
                    $credAccount = New-Object System.Management.Automation.PsCredential $username,$password
                }
            	New-SPManagedAccount -Credential $credAccount | Out-Null
            }
            Else 
            {
                Write-Host -ForegroundColor White " - Managed account $username already exists."
            }
			# The following was suggested by Matthias Einig (http://www.codeplex.com/site/users/view/matein78)
			# And inspired by http://todd-carter.com/post/2010/05/03/Give-your-Application-Pool-Accounts-A-Profile.aspx & http://blog.brainlitter.com/archive/2010/06/08/how-to-revolve-event-id-1511-windows-cannot-find-the-local-profile-on-windows-server-2008.aspx
	        Write-Host -ForegroundColor White " - Creating local profile for $username..." -NoNewline
	        Try
	    	{
				$credAccount = New-Object System.Management.Automation.PsCredential $username,$password
				$ManagedAccountDomain,$ManagedAccountUser = $username -Split "\\"
				# Add managed account to local admins (very) temporarily so it can log in and create its profile
	    		([ADSI]"WinNT://$env:COMPUTERNAME/Administrators,group").Add("WinNT://$ManagedAccountDomain/$ManagedAccountUser")
				If (-not $?) {$AlreadyAdmin = $true}
				# Spawn a command window using the managed account's credentials, create the profile, and exit immediately
				Start-Process -FilePath "$env:SYSTEMROOT\System32\cmd.exe" -ArgumentList "/C" -LoadUserProfile -NoNewWindow -Credential $credAccount
				# Remove managed account from local admins unless it was already there
	    		If (-not $AlreadyAdmin) {([ADSI]"WinNT://$env:COMPUTERNAME/Administrators,group").Remove("WinNT://$ManagedAccountDomain/$ManagedAccountUser")}
				Write-Host -BackgroundColor Blue -ForegroundColor Black "Done."
			}
			Catch 
			{
				$_
				Write-Host -ForegroundColor White "."
				Write-Warning " - Could not create local user profile for $username"
			}
        }
	}
	Write-Host -ForegroundColor White " - Done Adding Managed Accounts"
	WriteLine
}
#EndRegion

#Region Return SP Service Account
Function Get-spserviceaccountxml([xml]$xmlinput)
{
    $spservice = $xmlinput.Configuration.Farm.ManagedAccounts.ManagedAccount | Where-Object { $_.CommonName -match "spservice" }
    return $spservice
}
#EndRegion

#Region Get or Create Hosted Services Application Pool
# ====================================================================================
# Func: Get-HostedServicesAppPool
# Desc: Creates and/or returns the Hosted Services Application Pool
# ====================================================================================
Function Get-HostedServicesAppPool ([xml]$xmlinput)
{
	$spservice = Get-spserviceaccountxml $xmlinput
	# Managed Account
   	$ManagedAccountGen = Get-SPManagedAccount | Where-Object {$_.UserName -eq $($spservice.username)}
   	if ($ManagedAccountGen -eq $NULL) { throw " - Managed Account $($spservice.username) not found" }
	# App Pool
   	$ApplicationPool = Get-SPServiceApplicationPool "SharePoint Hosted Services" -ea SilentlyContinue
   	If ($ApplicationPool -eq $null)
	{
    	Write-Host -ForegroundColor White " - Creating SharePoint Hosted Services Application Pool..."
		$ApplicationPool = New-SPServiceApplicationPool -Name "SharePoint Hosted Services" -account $ManagedAccountGen
       	If (-not $?) { throw "Failed to create the application pool" }
   	}
	Return $ApplicationPool
}
#EndRegion

#Region Create Basic Service Application
# ===================================================================================
# Func: CreateBasicServiceApplication
# Desc: Creates a basic service application
# ===================================================================================
Function CreateBasicServiceApplication()
{
    param
    (
        [Parameter(Mandatory=$True)][ValidateNotNullOrEmpty()]
        [String]$ServiceConfig,
        [Parameter(Mandatory=$True)][ValidateNotNullOrEmpty()]
        [String]$ServiceInstanceType,
        [Parameter(Mandatory=$True)][ValidateNotNullOrEmpty()]
        [String]$ServiceName,
        [Parameter(Mandatory=$False)][ValidateNotNullOrEmpty()]
        [String]$ServiceProxyName,
		[Parameter(Mandatory=$True)][ValidateNotNullOrEmpty()]
        [String]$ServiceGetCmdlet,
		[Parameter(Mandatory=$False)][ValidateNotNullOrEmpty()]
        [String]$ServiceProxyGetCmdlet,
        [Parameter(Mandatory=$True)][ValidateNotNullOrEmpty()]
        [String]$ServiceNewCmdlet,
        [Parameter(Mandatory=$False)][ValidateNotNullOrEmpty()]
        [String]$ServiceProxyNewCmdlet,
        [Parameter(Mandatory=$False)][ValidateNotNullOrEmpty()]
		[String]$ServiceProxyNewParams
	)
	
	Try
	{
		$ApplicationPool = Get-HostedServicesAppPool ($xmlinput)
		Write-Host -ForegroundColor White " - Provisioning $($ServiceName)..."
	    # get the service instance
	    $ServiceInstances = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq $ServiceInstanceType}
		$ServiceInstance = $ServiceInstances | ? {$_.Server.Address -eq $env:COMPUTERNAME}
	    If (!$ServiceInstance) { throw " - Failed to get service instance - check product version (Standard vs. Enterprise)" }
		# Start Service instance
	  	Write-Host -ForegroundColor White " - Checking $($ServiceInstance.TypeName) instance..."
	    If (($ServiceInstance.Status -eq "Disabled") -or ($ServiceInstance.Status -ne "Online"))
  		{  
            Write-Host -ForegroundColor White " - Starting $($ServiceInstance.TypeName) instance..."
			$ServiceInstance.Provision()
            If (-not $?) { throw " - Failed to start $($ServiceInstance.TypeName) instance" }
            # Wait
  			Write-Host -ForegroundColor Blue " - Waiting for $($ServiceInstance.TypeName) instance..." -NoNewline
  			While ($ServiceInstance.Status -ne "Online") 
  			{
 				Write-Host -ForegroundColor Blue "." -NoNewline
  				sleep 1
   				$ServiceInstances = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq $ServiceInstanceType}
				$ServiceInstance = $ServiceInstances | ? {$_.Server.Address -eq $env:COMPUTERNAME}
   			}
   				Write-Host -BackgroundColor Blue -ForegroundColor Black $($ServiceInstance.Status)
        }
		Else 
		{
   			Write-Host -ForegroundColor White " - $($ServiceInstance.TypeName) instance already started."
		}
		# Check if our new cmdlets are available yet,  if not, re-load the SharePoint PS Snapin
		If (!(Get-Command $ServiceGetCmdlet -ErrorAction SilentlyContinue))
		{
			Write-Host -ForegroundColor White " - Re-importing SP PowerShell Snapin to enable new cmdlets..."
			Remove-PSSnapin Microsoft.SharePoint.PowerShell
			Load-SharePoint-Powershell
		}
		$GetServiceApplication = Invoke-Expression "$ServiceGetCmdlet | ? {`$_.Name -eq `"$ServiceName`"}"
		If ($GetServiceApplication -eq $null)
		{
			Write-Host -ForegroundColor White " - Provisioning $ServiceName..."
			$NewServiceApplication = Invoke-Expression "$ServiceNewCmdlet -Name `"$ServiceName`" -ApplicationPool `$ApplicationPool"
			Write-Host -ForegroundColor White " - Provisioning $ServiceName Proxy..."
			# Because apparently the teams developing the cmdlets for the various service apps didn't communicate with each other, we have to account for the different ways each proxy is provisioned!
			Switch ($ServiceInstanceType)
			{
				"Microsoft.Office.Server.PowerPoint.SharePoint.Administration.PowerPointWebServiceInstance" {& $ServiceProxyNewCmdlet -Name "$ServiceProxyName" -ServiceApplication $NewServiceApplication -AddToDefaultGroup | Out-Null}
				"Microsoft.Office.Visio.Server.Administration.VisioGraphicsServiceInstance" {& $ServiceProxyNewCmdlet -Name "$ServiceProxyName" -ServiceApplication $NewServiceApplication.Name | Out-Null}
				"Microsoft.PerformancePoint.Scorecards.BIMonitoringServiceInstance" {& $ServiceProxyNewCmdlet -Name "$ServiceProxyName" -ServiceApplication $NewServiceApplication -Default | Out-Null}
				"Microsoft.Office.Excel.Server.MossHost.ExcelServerWebServiceInstance" {} # Do nothing because there is no cmdlet to create this services proxy
				"Microsoft.Office.Access.Server.MossHost.AccessServerWebServiceInstance" {} # Do nothing because there is no cmdlet to create this services proxy
				"Microsoft.Office.Word.Server.Service.WordServiceInstance" {} # Do nothing because there is no cmdlet to create this services proxy
				Default {& $ServiceProxyNewCmdlet -Name "$ServiceProxyName" -ServiceApplication $NewServiceApplication | Out-Null}
			}
		}
		Else
		{
			Write-Host -ForegroundColor White " - $ServiceName already provisioned."
		}
	}
	Catch
	{
		Write-Output $_
		Pause
	}
}
#EndRegion

#Region Sandboxed Code Service
# ===================================================================================
# Func: StartSandboxedCodeService
# Desc: Starts the SharePoint Foundation Sandboxed (User) Code Service
# ===================================================================================
Function StartSandboxedCodeService
{
    If ($($xmlinput.Configuration.Farm.Services.SandboxedCodeService.Start) -eq $true)
	{
		WriteLine
		Write-Host -ForegroundColor White " - Starting Sandboxed Code Service"
		$SandboxedCodeServices = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq "Microsoft.SharePoint.Administration.SPUserCodeServiceInstance"}
   	 	$SandboxedCodeService = $SandboxedCodeServices | ? {$_.Server.Address -eq $env:COMPUTERNAME}
		If ($SandboxedCodeService.Status -ne "Online")
   	 	{
    		try
    		{
    			Write-Host -ForegroundColor White " - Starting Microsoft SharePoint Foundation Sandboxed Code Service..."
				UpdateProcessIdentity ($SandboxedCodeService)
    			$SandboxedCodeService.Provision()
    			If (-not $?) {throw " - Failed to start Sandboxed Code Service"}
    		}
    		catch 
        	{
        	    " - An error occurred starting the Microsoft SharePoint Foundation Sandboxed Code Service"
        	}
    		#Wait
        	Write-Host -ForegroundColor Blue " - Waiting for Sandboxed Code service..." -NoNewline
        	While ($SandboxedCodeService.Status -ne "Online") 
        	{
				Write-Host -ForegroundColor Blue "." -NoNewline
				sleep 1
				$SandboxedCodeServices = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq "Microsoft.SharePoint.Administration.SPUserCodeServiceInstance"}
				$SandboxedCodeService = $SandboxedCodeServices | ? {$_.Server.Address -eq $env:COMPUTERNAME}
			}
			Write-Host -BackgroundColor Blue -ForegroundColor Black $($SandboxedCodeService.Status)
    	}
		Else 
		{
			Write-Host -ForegroundColor White " - Sandboxed Code Service already started."
		}
		WriteLine
	}
}
#EndRegion

#Region Create Metadata Service Application
# ===================================================================================
# Func: CreateMetadataServiceApp
# Desc: Managed Metadata Service Application
# ===================================================================================
Function CreateMetadataServiceApp([xml]$xmlinput)
{
    If ($($xmlinput.Configuration.ServiceApps.ManagedMetadataServiceApp.Provision) -eq $true) 
    {
    	WriteLine
		try
    	{
			$MetaDataDB = $DBPrefix+$xmlinput.Configuration.ServiceApps.ManagedMetadataServiceApp.Database
            $FarmAcct = $xmlinput.Configuration.Farm.Account.Username
			$MetadataServiceName = $xmlinput.Configuration.ServiceApps.ManagedMetadataServiceApp.Name
			$MetadataServiceProxyName = $xmlinput.Configuration.ServiceApps.ManagedMetadataServiceApp.ProxyName
			If($MetadataServiceName -eq $null) {$MetadataServiceName = "Metadata Service Application"}
			If($MetadataServiceProxyName -eq $null) {$MetadataServiceProxyName = $MetadataServiceName}
			Write-Host -ForegroundColor White " - Provisioning Managed Metadata Service Application"
			$ApplicationPool = Get-HostedServicesAppPool ($xmlinput)
			Write-Host -ForegroundColor White " - Starting Managed Metadata Service:"
            # Get the service instance
            $MetadataServiceInstances = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq "Microsoft.SharePoint.Taxonomy.MetadataWebServiceInstance"}
            $MetadataServiceInstance = $MetadataServiceInstances | ? {$_.Server.Address -eq $env:COMPUTERNAME}
			If (-not $?) { throw " - Failed to find Metadata service instance" }
            # Start Service instances
			If($MetadataServiceInstance.Status -eq "Disabled")
  			{ 
        	    Write-Host -ForegroundColor White " - Starting Metadata Service Instance..."
           	    $MetadataServiceInstance.Provision()
                If (-not $?) { throw " - Failed to start Metadata service instance" }
				# Wait
    			Write-Host -ForegroundColor Blue " - Waiting for Metadata service..." -NoNewline
    			While ($MetadataServiceInstance.Status -ne "Online") 
    			{
    				Write-Host -ForegroundColor Blue "." -NoNewline
    				sleep 1
    				$MetadataServiceInstances = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq "Microsoft.SharePoint.Taxonomy.MetadataWebServiceInstance"}
					$MetadataServiceInstance = $MetadataServiceInstances | ? {$_.Server.Address -eq $env:COMPUTERNAME}
    			}
    			Write-Host -BackgroundColor Blue -ForegroundColor Black ($MetadataServiceInstance.Status)
			}
			Else {Write-Host -ForegroundColor White " - Managed Metadata Service already started."}

     	    # Create a Metadata Service Application
          	If((Get-SPServiceApplication | ? {$_.GetType().ToString() -eq "Microsoft.SharePoint.Taxonomy.MetadataWebServiceApplication"}) -eq $null)
    	  	{      
    			# Create Service App
       			Write-Host -ForegroundColor White " - Creating Metadata Service Application..."
                $MetaDataServiceApp = New-SPMetadataServiceApplication -Name $MetadataServiceName -ApplicationPool $ApplicationPool -DatabaseName $MetaDataDB -AdministratorAccount $FarmAcct -FullAccessAccount $FarmAcct
                If (-not $?) { throw " - Failed to create Metadata Service Application" }
                # create proxy
    			Write-Host -ForegroundColor White " - Creating Metadata Service Application Proxy..."
                $MetaDataServiceAppProxy = New-SPMetadataServiceApplicationProxy -Name $MetadataServiceProxyName -ServiceApplication $MetaDataServiceApp -DefaultProxyGroup
                If (-not $?) { throw " - Failed to create Metadata Service Application Proxy" }
    			Write-Host -ForegroundColor White " - Granting rights to Metadata Service Application..."
    			# Get ID of "Managed Metadata Service"
    			$MetadataServiceAppToSecure = Get-SPServiceApplication | ? {$_.GetType().ToString() -eq "Microsoft.SharePoint.Taxonomy.MetadataWebServiceApplication"}
    			$MetadataServiceAppIDToSecure = $MetadataServiceAppToSecure.Id
    			# Create a variable that contains the list of administrators for the service application 
    			$MetadataServiceAppSecurity = Get-SPServiceApplicationSecurity $MetadataServiceAppIDToSecure
        		foreach ($account in ($xmlinput.Configuration.Farm.ManagedAccounts.ManagedAccount)) ##| Where-Object { $_.CommonName -match "content" }))
        		{
        			# Create a variable that contains the claims principal for the service accounts
        			$AccountPrincipal = New-SPClaimsPrincipal -Identity $account.username -IdentityType WindowsSamAccountName			
        			# Give permissions to the claims principal you just created
        			Grant-SPObjectSecurity $MetadataServiceAppSecurity -Principal $AccountPrincipal -Rights "Full Access to Term Store"
                }    			
    			# Apply the changes to the Metadata Service application
    			Set-SPServiceApplicationSecurity $MetadataServiceAppIDToSecure -objectSecurity $MetadataServiceAppSecurity
    			Write-Host -ForegroundColor White " - Done creating Managed Metadata Service Application."
          	}
    	  	Else 
			{
				Write-Host -ForegroundColor White " - Managed Metadata Service Application already provisioned."
			}
    	}
    	catch
    	{
    		Write-Output $_ 
    	}
    }
	WriteLine
}
#EndRegion

#Region Assign Certificate
# ===================================================================================
# Func: AssignCert
# Desc: Create and assign SSL Certificate
# ===================================================================================
Function AssignCert([xml]$xmlinput)
{
	# Load IIS WebAdministration Snapin/Module
	# Inspired by http://stackoverflow.com/questions/1924217/powershell-load-webadministration-in-ps1-script-on-both-iis-7-and-iis-7-5
    $QueryOS = Gwmi Win32_OperatingSystem
    $QueryOS = $QueryOS.Version 
    $OS = ""
    If ($QueryOS.contains("6.1")) {$OS = "Win2008R2"}
    ElseIf ($QueryOS.contains("6.0")) {$OS = "Win2008"}
    
	Try
	{
		If ($OS -eq "Win2008")
		{
			If (!(Get-PSSnapin WebAdministration -ErrorAction SilentlyContinue))
			{	 
  				If (!(Test-Path $env:ProgramFiles\IIS\PowerShellSnapin\IIsConsole.psc1)) 
				{
					Start-Process -Wait -NoNewWindow -FilePath msiexec.exe -ArgumentList "/i `"$bits\PrerequisiteInstallerFiles\iis7psprov_x64.msi`" /passive /promptrestart"
				}
				Add-PSSnapin WebAdministration
			}
		}
		Else # Win2008R2
		{ 
  			Import-Module WebAdministration
		}
	}
	Catch
	{
		Write-Host -ForegroundColor White " - Could not load IIS Administration module."
	}
	Write-Host -ForegroundColor White " - Assigning certificate to site `"https://$SSLHostHeader`:$SSLPort`""
	# If our SSL host header is a FQDN containing the local domain, look for an existing wildcard cert
	If ($SSLHostHeader -like "*.$env:USERDNSDOMAIN")
	{
		Write-Host -ForegroundColor White " - Looking for existing `"*.$env:USERDNSDOMAIN`" wildcard certificate..."
		$Cert = Get-ChildItem cert:\LocalMachine\My | ? {$_.Subject -like "CN=``*.$env:USERDNSDOMAIN*"}
	}
	Else
	{
		Write-Host -ForegroundColor White " - Looking for existing `"$SSLHostHeader`" certificate..."
		$Cert = Get-ChildItem cert:\LocalMachine\My | ? {$_.Subject -eq "CN=$SSLHostHeader"}
	}
	If (!$Cert)
	{
		Write-Host -ForegroundColor White " - None found."
		$MakeCert = "$env:ProgramFiles\Microsoft Office Servers\14.0\Tools\makecert.exe"
		If (Test-Path "$MakeCert")
		{
			Write-Host -ForegroundColor White " - Creating new self-signed certificate..."
			If ($SSLHostHeader -like "*.$env:USERDNSDOMAIN")
			{
				# Create a new wildcard cert so we can potentially use it on other sites too
				Start-Process -NoNewWindow -Wait -FilePath "$MakeCert" -ArgumentList "-r -pe -n `"CN=*.$env:USERDNSDOMAIN`" -eku 1.3.6.1.5.5.7.3.1 -ss My -sr localMachine -sky exchange -sp `"Microsoft RSA SChannel Cryptographic Provider`" -sy 12"
				$Cert = Get-ChildItem cert:\LocalMachine\My | ? {$_.Subject -like "CN=``*.$env:USERDNSDOMAIN*"}
			}
			Else
			{
				# Just create a cert that matches the SSL host header
				Start-Process -NoNewWindow -Wait -FilePath "$MakeCert" -ArgumentList "-r -pe -n `"CN=$SSLHostHeader`" -eku 1.3.6.1.5.5.7.3.1 -ss My -sr localMachine -sky exchange -sp `"Microsoft RSA SChannel Cryptographic Provider`" -sy 12"
				$Cert = Get-ChildItem cert:\LocalMachine\My | ? {$_.Subject -eq "CN=$SSLHostHeader"}
			}
		}
		Else 
		{
			Write-Host -ForegroundColor White " - `"$MakeCert`" not found."
			Write-Host -ForegroundColor White " - Looking for any machine-named certificates we can use..."
			# Select the first certificate with the most recent valid date
			$Cert = Get-ChildItem cert:\LocalMachine\My | ? {$_.Subject -like "*$env:COMPUTERNAME"} | Sort-Object NotBefore -Desc | Select-Object -First 1
			If (!$Cert)
			{
				Write-Host -ForegroundColor White " - None found, skipping certificate creation."
			}
		}
	}
	If ($Cert)
	{
		$CertSubject = $Cert.Subject
		Write-Host -ForegroundColor White " - Certificate `"$CertSubject`" found."
		# Fix up the cert subject name to a file-friendly format
		$CertSubjectName = $CertSubject.Split(",")[0] -replace "CN=","" -replace "\*","wildcard"
		# Export our certificate to a file, then import it to the Trusted Root Certification Authorites store so we don't get nasty browser warnings
		# This will actually only work if the Subject and the host part of the URL are the same
		# Borrowed from https://www.orcsweb.com/blog/james/powershell-ing-on-windows-server-how-to-import-certificates-using-powershell/
		Write-Host -ForegroundColor White " - Exporting `"$CertSubject`" to `"$CertSubjectName.cer`"..."
		$Cert.Export("Cert") | Set-Content "$env:TEMP\$CertSubjectName.cer" -Encoding byte
		$Pfx = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
		Write-Host -ForegroundColor White " - Importing `"$CertSubjectName.cer`" to Local Machine\Root..."
		$Pfx.Import("$env:TEMP\$CertSubjectName.cer")
		$Store = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root","LocalMachine")
		$Store.Open("MaxAllowed")
		$Store.Add($Pfx)
		$Store.Close()
		Write-Host -ForegroundColor White " - Assigning certificate `"$CertSubject`" to SSL-enabled site..."
		#Set-Location IIS:\SslBindings -ErrorAction Inquire
		$Cert | New-Item IIS:\SslBindings\0.0.0.0!$SSLPort -ErrorAction SilentlyContinue | Out-Null
		Write-Host -ForegroundColor White " - Certificate has been assigned to site `"https://$SSLHostHeader`:$SSLPort`""
	}
	Else {Write-Host -ForegroundColor White " - No certificates were found, and none could be created."}
	$Cert = $null
}
#EndRegion

#Region Create Web Applications
# ===================================================================================
# Func: CreateWebApplications
# Desc: Create and  configure the required web applications
# ===================================================================================
Function CreateWebApplications([xml]$xmlinput)
{
	WriteLine
	If ($xmlinput.Configuration.WebApplications)
	{
		Write-Host " - Creating web applications" -ForegroundColor White 
        ForEach ($webApp in $xmlinput.Configuration.WebApplications.WebApplication)
        {
			CreateWebApp $webApp
			ConfigureObjectCache $webApp
            WriteLine
        }
    }
	WriteLine
}
# ===================================================================================
# Func: CreateWebApp
# Desc: Create the web application
# ===================================================================================
Function CreateWebApp([System.Xml.XmlElement]$webApp)
{
	$account = $webApp.applicationPoolAccount
    $WebAppName = $webApp.name
    $AppPool = $webApp.applicationPool
    $database = $DBPrefix+$webApp.databaseName
    $url = $webApp.url
    $port = $webApp.port
	$useSSL = $false
	$InstalledOfficeServerLanguages = (Get-Item "HKLM:\Software\Microsoft\Office Server\14.0\InstalledLanguages").GetValueNames() | ? {$_ -ne ""}
    If ($url -like "https://*") {$UseSSL = $true; $HostHeader = $url -replace "https://",""}        
    Else {$HostHeader = $url -replace "http://",""}
    $GetSPWebApplication = Get-SPWebApplication | Where-Object {$_.DisplayName -eq $WebAppName}
	If ($GetSPWebApplication -eq $null)
   	{
        Write-Host -ForegroundColor White " - Creating Web App `"$WebAppName`""
   		If ($($webApp.useClaims) -eq $true)
  		{
  			# Configure new web app to use Claims-based authentication
   			$AuthProvider = New-SPAuthenticationProvider -UseWindowsIntegratedAuthentication
   			New-SPWebApplication -Name $WebAppName -ApplicationPoolAccount $account -ApplicationPool $AppPool -DatabaseName $database -HostHeader $HostHeader -Url $url -Port $port -SecureSocketsLayer:$UseSSL -AuthenticationProvider $AuthProvider | Out-Null
			If ((Gwmi Win32_OperatingSystem).Version -ne "6.1.7601") # If we aren't running SP1 for Win2008 R2, we may need the claims hotfix
			{
				[bool]$ClaimsHotfixRequired = $true
				Write-Host -ForegroundColor Yellow " - Web Applications using Claims authentication require an update"
				Write-Host -ForegroundColor Yellow " - Apply the http://go.microsoft.com/fwlink/?LinkID=184705 update after setup."
			}
   		}
   		Else
   		{
    		# Create the web app using Classic mode authentication
   			New-SPWebApplication -Name $WebAppName -ApplicationPoolAccount $account -ApplicationPool $AppPool -DatabaseName $database -HostHeader $HostHeader -Url $url -Port $port -SecureSocketsLayer:$UseSSL | Out-Null
   		}
		If ($UseSSL)
		{
    		$script:SSLHostHeader = $HostHeader
			$script:SSLPort = $Port
			AssignCert
		}
        SetupManagedPaths $webApp
	}	
    Else {Write-Host -ForegroundColor White " - Web app `"$WebAppName`" already provisioned."}
	ForEach ($SiteCollection in $webApp.SiteCollections.SiteCollection)
	{
		$SiteCollectionName = $SiteCollection.name
		$SiteURL = $SiteCollection.siteURL
		$template = $SiteCollection.template
		$OwnerAlias = $SiteCollection.Owner
		$LCID = $SiteCollection.LCID
		$GetSPSiteCollection = Get-SPSite | Where-Object {$_.Url -eq $SiteURL}
		If ($GetSPSiteCollection -eq $null)
		{
			Write-Host -ForegroundColor White " - Creating Site Collection `"$SiteURL`"..."
			# Verify that the Language we're trying to create the site in is currently installed on the server
			$Culture = [System.Globalization.CultureInfo]::GetCultureInfo(([convert]::ToInt32($LCID)))
			$CultureDisplayName = $Culture.DisplayName
			If (!($InstalledOfficeServerLanguages | Where-Object {$_ -eq $Culture.Name}))
			{
		  		Write-Warning " - You must install the `"$Culture ($CultureDisplayName)`" Language Pack before you can create a site using LCID $LCID"
			}
			Else
			{
				Try
				{
					# If a template has been pre-specified, use it when creating the Portal site collection; otherwise, leave it blank so we can select one when the portal first loads
					If (($Template -ne $null) -and ($Template -ne "")) {New-SPSite -Url $SiteURL -OwnerAlias $OwnerAlias -SecondaryOwnerAlias $env:USERDOMAIN\$env:USERNAME -ContentDatabase $database -Description $SiteCollectionName -Name $SiteCollectionName -Language $LCID -Template $Template | Out-Null}
					Else {New-SPSite -Url $SiteURL -OwnerAlias $OwnerAlias -SecondaryOwnerAlias $env:USERDOMAIN\$env:USERNAME -ContentDatabase $database -Description $SiteCollectionName -Name $SiteCollectionName -Language $LCID | Out-Null}
				}
				Catch
				{
					Write-Output $_
					Write-Warning " - An error occurred creating Site Collection `"$SiteURL`"."
					Pause
				}
				# Add the Portal Site Connection to the web app, unless of course the current web app *is* the portal
				# Inspired by http://www.toddklindt.com/blog/Lists/Posts/Post.aspx?ID=264
				$PortalWebApp = $xmlinput.Configuration.WebApplications.WebApplication | Where {$_.Type -eq "Portal"}
				$PortalSiteColl = $PortalWebApp.SiteCollections.SiteCollection | Select-Object -First 1
				$SPSite = Get-SPSite $SiteURL
				If ($SPSite.URL -ne $PortalSiteColl.siteURL)
				{
					Write-Host -ForegroundColor White " - Setting the Portal Site Connection for `"$SiteCollectionName`"..."
					$SPSite.PortalName = $PortalSiteColl.Name
					$SPSite.PortalUrl = $PortalSiteColl.siteUrl
				}
			}
		}
		Else {Write-Host -ForegroundColor White " - Site `"$SiteCollectionName`" already provisioned."}
	}
}

# ===================================================================================
# Func: Set-WebAppUserPolicy
# AMW 1.7.2
# Desc: Set the web application user policy
# Refer to http://technet.microsoft.com/en-us/library/ff758656.aspx
# Updated based on Gary Lapointe example script to include Policy settings 18/10/2010
# ===================================================================================
Function Set-WebAppUserPolicy($wa, $userName, $displayName, $perm) 
{
    [Microsoft.SharePoint.Administration.SPPolicyCollection]$policies = $wa.Policies
    [Microsoft.SharePoint.Administration.SPPolicy]$policy = $policies.Add($userName, $displayName)
    [Microsoft.SharePoint.Administration.SPPolicyRole]$policyRole = $wa.PolicyRoles | where {$_.Name -eq $perm}
    if ($policyRole -ne $null) {
        $policy.PolicyRoleBindings.Add($policyRole)
    }
    $wa.Update()
}

# ===================================================================================
# Func: ConfigureObjectCache
# Desc: Applies the portal super accounts to the object cache for a web application
# ===================================================================================
Function ConfigureObjectCache([System.Xml.XmlElement]$webApp)
{
	Try
	{
   		$url = $webApp.Url + ":" + $webApp.Port
		$wa = Get-SPWebApplication | Where-Object {$_.DisplayName -eq $webApp.Name}
		$SuperUserAcc = $xmlinput.Configuration.Farm.ObjectCacheAccounts.SuperUser
		$SuperReaderAcc = $xmlinput.Configuration.Farm.ObjectCacheAccounts.SuperReader
		# If the web app is using Claims auth, change the user accounts to the proper syntax
		If ($wa.UseClaimsAuthentication -eq $true) 
		{
			$SuperUserAcc = 'i:0#.w|' + $SuperUserAcc
			$SuperReaderAcc = 'i:0#.w|' + $SuperReaderAcc
		}
		Write-Host -ForegroundColor White " - Applying object cache accounts to `"$url`"..."
        $wa.Properties["portalsuperuseraccount"] = $SuperUserAcc
	    Set-WebAppUserPolicy $wa $SuperUserAcc "Super User (Object Cache)" "Full Control"
        $wa.Properties["portalsuperreaderaccount"] = $SuperReaderAcc
	    Set-WebAppUserPolicy $wa $SuperReaderAcc "Super Reader (Object Cache)" "Full Read"
        $wa.Update()        
    	Write-Host -ForegroundColor White " - Done applying object cache accounts to `"$url`""
	}
	Catch
	{
		$_
		Write-Warning " - An error occurred applying object cache to `"$url`""
		Pause
	}
}
#EndRegion

#Region Setup Managed Paths
# ===================================================================================
# Func: SetupManagedPaths
# Desc: Sets up managed paths for a given web application
# ===================================================================================
Function SetupManagedPaths([System.Xml.XmlElement]$webApp)
{
	$url = $webApp.Url + ":" + $webApp.Port
    If ($url -like "*localhost*") {$url = $url -replace "localhost","$env:COMPUTERNAME"}
	Write-Host -ForegroundColor White " - Setting up managed paths for `"$url`""

	if ($webApp.ManagedPaths)
	{
	    foreach ($managedPath in $webApp.ManagedPaths.ManagedPath)
		{
            if ($managedPath.Delete -eq "true")
            {
                Write-Host -ForegroundColor White " - Deleting managed path `"$($managedPath.RelativeUrl)`" at `"$url`""            
                Remove-SPManagedPath -Identity $managedPath.RelativeUrl -WebApplication $url -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
            }
            else
            {
    			if ($managedPath.Explicit -eq "true")
    			{
    				Write-Host -ForegroundColor White " - Setting up explicit managed path `"$($managedPath.RelativeUrl)`" at `"$url`""
    			    New-SPManagedPath -RelativeUrl $managedPath.RelativeUrl -WebApplication $url -Explicit -ErrorAction SilentlyContinue | Out-Null
    			}
    			else
    			{
    				Write-Host -ForegroundColor White " - Setting up managed path `"$($managedPath.RelativeUrl)`" at `"$url`""
    			    New-SPManagedPath -RelativeUrl $managedPath.RelativeUrl -WebApplication $url -ErrorAction SilentlyContinue | Out-Null
    			}
            }
		}
	}

	Write-Host -ForegroundColor White " - Done setting up managed paths at `"$url`""
}
#EndRegion

#Region Create User Profile Service Application
# ===================================================================================
# Func: CreateUserProfileServiceApplication
# Desc: Create the User Profile Service Application
# ===================================================================================
Function CreateUserProfileServiceApplication([xml]$xmlinput)
{
    WriteLine
	# Based on http://sharepoint.microsoft.com/blogs/zach/Lists/Posts/Post.aspx?ID=50
	try
	{   
        $UserProfile = $xmlinput.Configuration.ServiceApps.UserProfileServiceApp
		$MySiteWebApp = $xmlinput.Configuration.WebApplications.WebApplication | Where {$_.type -eq "MySiteHost"} 
		$MySiteName = $MySiteWebApp.name
		$MySiteURL = $MySiteWebApp.url
		$MySitePort = $MySiteWebApp.port
		$MySiteDB = $DBPrefix+$MySiteWebApp.databaseName
		$MySiteAppPoolAcct = $MySiteWebApp.applicationPoolAccount
		$PortalWebApp = $xmlinput.Configuration.WebApplications.WebApplication | Where {$_.Type -eq "Portal"}
		$PortalAppPoolAcct = $PortalWebApp.applicationPoolAccount
        $FarmAcct = $xmlinput.Configuration.Farm.Account.Username
		$FarmAcctPWD = $xmlinput.Configuration.Farm.Account.Password
		$ContentAccessAcct = $xmlinput.Configuration.ServiceApps.EnterpriseSearchService.EnterpriseSearchServiceApplications.EnterpriseSearchServiceApplication.ContentAccessAccount
		If (($FarmAcctPWD -ne "") -and ($FarmAcctPWD -ne $null)) {$FarmAcctPWD = (ConvertTo-SecureString $FarmAcctPWD -AsPlainText -force)}
		$MySiteTemplate = $MySiteWebApp.SiteCollections.SiteCollection.Template
		$MySiteLCID = $MySiteWebApp.SiteCollections.SiteCollection.LCID
		$UserProfileServiceName = $UserProfile.Name
		$UserProfileServiceProxyName = $UserProfile.ProxyName
		If($UserProfileServiceName -eq $null) {$UserProfileServiceName = "User Profile Service Application"}
		If($UserProfileServiceProxyName -eq $null) {$UserProfileServiceProxyName = $UserProfileServiceName}

		[System.Management.Automation.PsCredential]$farmCredential  = GetFarmCredentials ($xmlinput)
		If ($($UserProfile.Provision) -eq $true) 
        {        
          	Write-Host -ForegroundColor White " - Provisioning $($UserProfile.Name)"
			$ApplicationPool = Get-HostedServicesAppPool ($xmlinput)
            # get the service instance
            $ProfileServiceInstances = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq "Microsoft.Office.Server.Administration.UserProfileServiceInstance"}
			$ProfileServiceInstance = $ProfileServiceInstances | ? {$_.Server.Address -eq $env:COMPUTERNAME}
            If (-not $?) { throw " - Failed to find User Profile Service instance" }
            # Start Service instance
  			Write-Host -ForegroundColor White " - Starting User Profile Service instance..."
            If (($ProfileServiceInstance.Status -eq "Disabled") -or ($ProfileServiceInstance.Status -ne "Online"))
  			{  
                $ProfileServiceInstance.Provision()
                If (-not $?) { throw " - Failed to start User Profile Service instance" }
                # Wait
  				Write-Host -ForegroundColor Blue " - Waiting for User Profile Service..." -NoNewline
  			    While ($ProfileServiceInstance.Status -ne "Online") 
  			    {
 					Write-Host -ForegroundColor Blue "." -NoNewline
  					sleep 1
   				    $ProfileServiceInstances = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq "Microsoft.Office.Server.Administration.UserProfileServiceInstance"}
					$ProfileServiceInstance = $ProfileServiceInstances | ? {$_.Server.Address -eq $env:COMPUTERNAME}
   			    }
   				Write-Host -BackgroundColor Blue -ForegroundColor Black $($ProfileServiceInstance.Status)
            }
          	# Create a Profile Service Application
          	If ((Get-SPServiceApplication | ? {$_.GetType().ToString() -eq "Microsoft.Office.Server.Administration.UserProfileApplication"}) -eq $null)
    	  	{      
    			# Create MySites Web Application
    			$GetSPWebApplication = Get-SPWebApplication | Where-Object {$_.DisplayName -eq $MySiteName}
    			If ($GetSPWebApplication -eq $Null)
    			{
    			    Write-Host -ForegroundColor White " - Creating Web App `"$MySiteName`"..."
    				New-SPWebApplication -Name $MySiteName -ApplicationPoolAccount $MySiteAppPoolAcct -ApplicationPool $MySiteAppPool -DatabaseName $MySiteDB -HostHeader $MySiteHostHeader -Url $MySiteURL -Port $MySitePort -SecureSocketsLayer:$MySiteUseSSL | Out-Null
    			}
    			Else
    			{
    				Write-Host -ForegroundColor White " - Web app `"$MySiteName`" already provisioned."
    			}
    			
                # Create MySites Site Collection
    			If ((Get-SPContentDatabase | Where-Object {$_.Name -eq $MySiteDB})-eq $null)
    			{
    				Write-Host -ForegroundColor White " - Creating My Sites content DB..."
    				$NewMySitesDB = New-SPContentDatabase -Name $MySiteDB -WebApplication "$MySiteURL`:$MySitePort"
    				If (-not $?) { throw " - Failed to create My Sites content DB" }
    			}
    			If ((Get-SPSite | Where-Object {(($_.Url -like "$MySiteURL*") -and ($_.Port -eq "$MySitePort")) -eq $null}))
    			{
    				Write-Host -ForegroundColor White " - Creating My Sites site collection $MySiteURL`:$MySitePort..."
    				# Verify that the Language we're trying to create the site in is currently installed on the server
                    $MySiteCulture = [System.Globalization.CultureInfo]::GetCultureInfo(([convert]::ToInt32($MySiteLCID))) 
    		        $MySiteCultureDisplayName = $MySiteCulture.DisplayName
					$InstalledOfficeServerLanguages = (Get-Item "HKLM:\Software\Microsoft\Office Server\14.0\InstalledLanguages").GetValueNames() | ? {$_ -ne ""}
					If (!($InstalledOfficeServerLanguages | Where-Object {$_ -eq $MySiteCulture.Name}))
    				{
    		            Write-Warning " - You must install the `"$MySiteCulture ($MySiteCultureDisplayName)`" Language Pack before you can create a site using LCID $MySiteLCID"
                        Pause
                        break
    	            }
    	            Else
    	            {
        				$NewMySitesCollection = New-SPSite -Url "$MySiteURL`:$MySitePort" -OwnerAlias $FarmAcct -SecondaryOwnerAlias $env:USERDOMAIN\$env:USERNAME -ContentDatabase $MySiteDB -Description $MySiteName -Name $MySiteName -Template $MySiteTemplate -Language $MySiteLCID | Out-Null
    				    If (-not $?) {throw " - Failed to create My Sites site collection"}
                        # Assign SSL certificate, if required
    			        If ($MySiteUseSSL)
    			        {
    				    	$SSLHostHeader = $MySiteHostHeader
    				    	$SSLPort = $MySitePort
    				    	AssignCert
    			        }
                    }
    			}
    			# Create Service App
    			Write-Host -ForegroundColor White " - Creating $UserProfileServiceName..."
				CreateUPSAsAdmin ($xmlinput)
				Write-Host -ForegroundColor Blue " - Waiting for $UserProfileServiceName..." -NoNewline
				$ProfileServiceApp = Get-SPServiceApplication |?{$_.DisplayName -eq $UserProfileServiceName}
    			While ($ProfileServiceApp.Status -ne "Online") 
    			{
					[int]$UPSWaitTime = 0
  					# Wait 2 minutes for either the UPS to be created, or the UAC prompt to time out
					While (($UPSWaitTime -lt 120) -and ($ProfileServiceApp.Status -ne "Online"))
					{
						Write-Host -ForegroundColor Blue "." -NoNewline
    					sleep 1
						$ProfileServiceApp = Get-SPServiceApplication |?{$_.DisplayName -eq $UserProfileServiceName}
						[int]$UPSWaitTime += 1
					}
					# If it still isn't Online after 2 minutes, prompt to try again
					If (!($ProfileServiceApp))
					{
						Write-Host -ForegroundColor Blue "."
						Write-Warning " - Timed out waiting for service creation (maybe a UAC prompt?)"
						Write-Host "`a`a`a" # System beeps
						Write-Host -ForegroundColor White " - Press any key to try again"
						$null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
						CreateUPSAsAdmin ($xmlinput)
						Write-Host -ForegroundColor Blue " - Waiting for $UserProfileServiceName..." -NoNewline
						$ProfileServiceApp = Get-SPServiceApplication |?{$_.DisplayName -eq $UserProfileServiceName}
					}
					Else {break}
    			}
    			Write-Host -BackgroundColor Blue -ForegroundColor Black $($ProfileServiceApp.Status)

				# Get our new Profile Service App
				$ProfileServiceApp = Get-SPServiceApplication |?{$_.DisplayName -eq $UserProfileServiceName}
				If (!($ProfileServiceApp)) {throw " - Could not get $UserProfileServiceName!"; Pause; break}
				
				# Create Proxy
    			Write-Host -ForegroundColor White " - Creating $UserProfileServiceName Proxy..."
                $ProfileServiceAppProxy  = New-SPProfileServiceApplicationProxy -Name "$UserProfileServiceProxyName" -ServiceApplication $ProfileServiceApp -DefaultProxyGroup
                If (-not $?) { throw " - Failed to create $UserProfileServiceName Proxy" }
    			
    			Write-Host -ForegroundColor White " - Granting rights to $UserProfileServiceName..."
    			# Create a variable that contains the guid for the User Profile service for which you want to delegate permissions
				$ServiceAppIDToSecure = Get-SPServiceApplication $($ProfileServiceApp.Id)

    			# Create a variable that contains the list of administrators for the service application 
				$ProfileServiceAppSecurity = Get-SPServiceApplicationSecurity $ServiceAppIDToSecure -Admin

    			# Create variables that contains the claims principals for MySite App Pool, Portal App Pool and Content Access accounts
    			$MySiteAppPoolAcctPrincipal = New-SPClaimsPrincipal -Identity $MySiteAppPoolAcct -IdentityType WindowsSamAccountName
				$PortalAppPoolAcctPrincipal = New-SPClaimsPrincipal -Identity $PortalAppPoolAcct -IdentityType WindowsSamAccountName
    			$ContentAccessAcctPrincipal = New-SPClaimsPrincipal -Identity $ContentAccessAcct -IdentityType WindowsSamAccountName

    			# Give 'Full Control' permissions to the MySite App Pool and Portal App Pool account claims principals
    			Grant-SPObjectSecurity $ProfileServiceAppSecurity -Principal $MySiteAppPoolAcctPrincipal -Rights "Full Control"
				Grant-SPObjectSecurity $ProfileServiceAppSecurity -Principal $PortalAppPoolAcctPrincipal -Rights "Full Control"
				# Give 'Retrieve People Data for Search Crawlers' permissions to the Content Access claims principal
    			Grant-SPObjectSecurity $ProfileServiceAppSecurity -Principal $ContentAccessAcctPrincipal -Rights "Retrieve People Data for Search Crawlers"

    			# Apply the changes to the User Profile service application
				Set-SPServiceApplicationSecurity $ServiceAppIDToSecure -objectSecurity $ProfileServiceAppSecurity -Admin
				
				# Grant the Portal App Pool account rights to the Profile DB
				$ProfileDB = $DBPrefix+$UserProfile.ProfileDB
				Write-Host -ForegroundColor White " - Granting $PortalAppPoolAcct rights to $ProfileDB..."
				Get-SPDatabase | ? {$_.Name -eq $ProfileDB} | Add-SPShellAdmin -UserName $PortalAppPoolAcct
				
				Write-Host -ForegroundColor White " - Enabling the Activity Feed Timer Job.."
				If ($ProfileServiceApp) {Get-SPTimerJob | ? {$_.TypeName -eq "Microsoft.Office.Server.ActivityFeed.ActivityFeedUPAJob"} | Enable-SPTimerJob}
				
    			Write-Host -ForegroundColor White " - Done creating $UserProfileServiceName."
          	}
    		# Start User Profile Synchronization Service
    		# Get User Profile Service
    		$ProfileServiceApp = Get-SPServiceApplication |?{$_.DisplayName -eq $UserProfileServiceName}
    		If ($ProfileServiceApp -and ($UserProfile.StartProfileSync -eq $true))
    		{
				If ($UserProfile.EnableNetBIOSDomainNames -eq $true)
				{
					Write-Host -ForegroundColor White " - Enabling NetBIOS domain names for $UserProfileServiceName..."
					$ProfileServiceApp.NetBIOSDomainNamesEnabled = 1
					$ProfileServiceApp.Update()
				}
				
				# Get User Profile Synchronization Service
    			Write-Host -ForegroundColor White " - Checking User Profile Synchronization Service..." -NoNewline
    			$ProfileSyncService = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq "Microsoft.Office.Server.Administration.ProfileSynchronizationServiceInstance"}
				# Attempt to start if there's only 1 Profile Sync Service instance in the farm as we probably don't want to start multiple Sync instances in the farm (running against the same Profile Service at least)
				If (!($ProfileSyncService.Count -gt 1) -and ($ProfileSyncService.Status -ne "Online"))
    			{
					# Inspired by http://technet.microsoft.com/en-us/library/ee721049.aspx
    				If (!($FarmAcct)) {$FarmAcct = (Get-SPFarm).DefaultServiceAccount}
    				If (!($FarmAcctPWD)) 
    				{
    					Write-Host -ForegroundColor White "`n"
    					$FarmAcctPWD = Read-Host -Prompt " - Please (re-)enter the Farm Account Password" -AsSecureString
    				}
    				Write-Host -ForegroundColor White "`n"
					# Check for an existing UPS credentials timer job (e.g. from a prior provisioning attempt), and delete it
    				$UPSCredentialsJob = Get-SPTimerJob | ? {$_.Name -eq "windows-service-credentials-FIMSynchronizationService"}
					If ($UPSCredentialsJob.Status -eq "Online")
					{
						Write-Host -ForegroundColor White " - Deleting exiting sync credentials timer job..."
						$UPSCredentialsJob.Delete()
					}
    				UpdateProcessIdentity ($ProfileSyncService)
    				Write-Host -ForegroundColor White " - Waiting for User Profile Synchronization Service..." -NoNewline
					# Provision the User Profile Sync Service
					$ProfileServiceApp.SetSynchronizationMachine($env:COMPUTERNAME, $ProfileSyncService.Id, $FarmAcct, (ConvertTo-PlainText $FarmAcctPWD))
    				If (($ProfileSyncService.Status -ne "Provisioning") -and ($ProfileSyncService.Status -ne "Online")) {Write-Host -ForegroundColor Blue "`n - Waiting for User Profile Synchronization Service to start..." -NoNewline}
    				##Else 
    				##{
					# Monitor User Profile Sync service status
    				While ($ProfileSyncService.Status -ne "Online")
    				{
    					While ($ProfileSyncService.Status -ne "Provisioning")
    					{
    						Write-Host -ForegroundColor Blue "." -NoNewline
    						Sleep 1
    						$ProfileSyncService = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq "Microsoft.Office.Server.Administration.ProfileSynchronizationServiceInstance"}
    					}
    					If ($ProfileSyncService.Status -eq "Provisioning")
    					{
    						Write-Host -BackgroundColor Blue -ForegroundColor Black $($ProfileSyncService.Status)
                			Write-Host -ForegroundColor Blue " - Provisioning User Profile Sync Service, please wait..." -NoNewline
    					}
    					While($ProfileSyncService.Status -eq "Provisioning" -and $ProfileSyncService.Status -ne "Disabled")
    					{
    						Write-Host -ForegroundColor Blue "." -NoNewline
    						sleep 1
    						$ProfileSyncService = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq "Microsoft.Office.Server.Administration.ProfileSynchronizationServiceInstance"}
    					}
    					If ($ProfileSyncService.Status -ne "Online")
    					{
    						Write-Host -ForegroundColor Red ".`a`a"
    						Write-Host -BackgroundColor Red -ForegroundColor Black " - User Profile Synchronization Service could not be started!"
    						break
    					}
    					Else
    					{
    						Write-Host -BackgroundColor Blue -ForegroundColor Black $($ProfileSyncService.Status)
    						# Need to restart IIS before we can do anything with the User Profile Sync Service
    						Write-Host -ForegroundColor White " - Restarting IIS..."
    						Start-Process -FilePath iisreset.exe -ArgumentList "-noforce" -Wait -NoNewWindow
    					}
    				}
    				##}
    			}
    			Else {Write-Host -ForegroundColor White "Already started."}
    		}
    		Else 
    		{
    			Write-Host -ForegroundColor White " - Could not get User Profile Service, or StartProfileSync is False."
    		}
        }
	}
	catch
    {
        Write-Output $_
		Pause
    }
	WriteLine
}
# ===================================================================================
# Func: CreateUPSAsAdmin
# Desc: Create the User Profile Service Application itself as the Farm Admin account, in a session with elevated privileges
# 		This incorporates the workaround by @harbars & @glapointe http://www.harbar.net/archive/2010/10/30/avoiding-the-default-schema-issue-when-creating-the-user-profile.aspx
# 		Modified to work within AutoSPInstaller (to pass our script variables to the Farm Account credential's Powershell session)
# ===================================================================================

Function CreateUPSAsAdmin([xml]$xmlinput)
{
	try
	{
		$MySiteWebApp = $xmlinput.Configuration.WebApplications.WebApplication | Where {$_.type -eq "MySiteHost"}
		$MySiteURL = $MySiteWebApp.url
		$MySitePort = $MySiteWebApp.port
        $FarmAcct = $xmlinput.Configuration.Farm.Account.Username
		$UserProfileServiceName = $UserProfile.Name
		$ProfileDB = $DBPrefix+$UserProfile.ProfileDB
		$SyncDB = $DBPrefix+$UserProfile.SyncDB
		$SocialDB = $DBPrefix+$UserProfile.SocialDB
       	$ApplicationPool = Get-HostedServicesAppPool ($xmlinput)
		[System.Management.Automation.PsCredential]$farmCredential  = GetFarmCredentials ($xmlinput)
		$ScriptFile = "$env:SystemDrive\AutoSPInstaller-ScriptBlock.ps1"
		# Write the script block, with expanded variables to a temporary script file that the Farm Account can get at
		Write-Output "Write-Host -ForegroundColor White `"Creating $UserProfileServiceName as $FarmAcct...`"" | Out-File $ScriptFile -Width 400
		Write-Output "Add-PsSnapin Microsoft.SharePoint.PowerShell" | Out-File $ScriptFile -Width 400 -Append
		Write-Output "`$NewProfileServiceApp = New-SPProfileServiceApplication -Name `"$UserProfileServiceName`" -ApplicationPool `"$($ApplicationPool.Name)`" -ProfileDBName $ProfileDB -ProfileSyncDBName $SyncDB -SocialDBName $SocialDB -MySiteHostLocation `"$MySiteURL`:$MySitePort`"" | Out-File $ScriptFile -Width 400 -Append
		Write-Output "If (-not `$?) {Write-Error `" - Failed to create $UserProfileServiceName`"; Write-Host `"Press any key to exit...`"; `$null = `$host.UI.RawUI.ReadKey`(`"NoEcho,IncludeKeyDown`"`)}" | Out-File $ScriptFile -Width 400 -Append
		# Grant the current install account rights to the newly-created Profile DB - needed since it's going to be running PowerShell commands against it
		Write-Output "`$ProfileDBId = Get-SPDatabase | ? {`$_.Name -eq `"$ProfileDB`"}" | Out-File $ScriptFile -Width 400 -Append
		Write-Output "Add-SPShellAdmin -UserName `"$env:USERDOMAIN\$env:USERNAME`" -database `$ProfileDBId" | Out-File $ScriptFile -Width 400 -Append
		# Start a process under the Farm Account's credentials, then spawn an elevated process within to finally execute the script file that actually creates the UPS
		Start-Process $PSHOME\powershell.exe -Credential $FarmCredential -ArgumentList "-Command Start-Process $PSHOME\powershell.exe -ArgumentList `"'$ScriptFile'`" -Verb Runas" -Wait
	}
	catch 
	{
		Write-Output $_
		Pause
	}
	finally 
	{
		# Delete the temporary script file if we were successful in creating the UPA
		$ProfileServiceApp = Get-SPServiceApplication | ? {$_.DisplayName -eq $UserProfileServiceName}
		If ($ProfileServiceApp) {Remove-Item -Path $ScriptFile -ErrorAction SilentlyContinue}
	}
}
#EndRegion

#Region Create State Service Application
Function CreateStateServiceApp([xml]$xmlinput)
{
    $StateService = $xmlinput.Configuration.ServiceApps.StateService
	If ($($StateService.Provision) -eq $true) 
	{
		WriteLine
		try
		{
			$StateServiceDB = $DBPrefix+$StateService.Database
			$StateServiceName = $StateService.Name
			$StateServiceProxyName = $StateService.ProxyName
			If ($StateServiceName -eq $null) {$StateServiceName = "State Service Application"}
			If ($StateServiceProxyName -eq $null) {$StateServiceProxyName = $StateServiceName}
			$GetSPStateServiceApplication = Get-SPStateServiceApplication
			If ($GetSPStateServiceApplication -eq $Null)
			{
				Write-Host -ForegroundColor White " - Provisioning State Service Application..."
				New-SPStateServiceDatabase -Name $StateServiceDB | Out-Null
				New-SPStateServiceApplication -Name $StateServiceName -Database $StateServiceDB | Out-Null
				Get-SPStateServiceDatabase | Initialize-SPStateServiceDatabase | Out-Null
				Write-Host -ForegroundColor White " - Creating State Service Application Proxy..."
				Get-SPStateServiceApplication | New-SPStateServiceApplicationProxy -Name $StateServiceProxyName -DefaultProxyGroup | Out-Null
				Write-Host -ForegroundColor White " - Done creating State Service Application."
			}
			Else {Write-Host -ForegroundColor White " - State Service Application already provisioned."}
		}
		catch
		{
			Write-Output $_
		}
		WriteLine
	}
}
#EndRegion

#Region Create SP Usage Application
# ===================================================================================
# Func: CreateSPUsageApp
# Desc: Creates the Usage and Health Data Collection service application
# ===================================================================================
Function CreateSPUsageApp([xml]$xmlinput)
{
    If ($($xmlinput.Configuration.ServiceApps.SPUsageService.Provision) -eq $true) 
	{
		WriteLine
		try
		{
			$DBServer =  $xmlinput.Configuration.Farm.Database.DBServer
			$SPUsageApplicationName = $xmlinput.Configuration.ServiceApps.SPUsageService.Name
			$SPUsageDB = $DBPrefix+$xmlinput.Configuration.ServiceApps.SPUsageService.Database
			$GetSPUsageApplication = Get-SPUsageApplication
			If ($GetSPUsageApplication -eq $Null)
			{
				Write-Host -ForegroundColor White " - Provisioning SP Usage Application..."
				New-SPUsageApplication -Name $SPUsageApplicationName -DatabaseServer $DBServer -DatabaseName $SPUsageDB | Out-Null
				# Need this to resolve a known issue with the Usage Application Proxy not automatically starting/provisioning
				# Thanks and credit to Jesper Nygaard Schiøtt (jesper@schioett.dk) per http://autospinstaller.codeplex.com/Thread/View.aspx?ThreadId=237578 ! 
				Write-Host -ForegroundColor White " - Fixing Usage and Health Data Collection Proxy..."
				$SPUsageApplicationProxy = Get-SPServiceApplicationProxy | where {$_.DisplayName -eq $SPUsageApplicationName}
				$SPUsageApplicationProxy.Provision()
				# End Usage Proxy Fix
				Write-Host -ForegroundColor White " - Done provisioning SP Usage Application."
			}
			Else {Write-Host -ForegroundColor White " - SP Usage Application already provisioned."}
		}
		catch
		{
			Write-Output $_
		}
		WriteLine
	}
}
#EndRegion

#Region Create Web Analytics Service Application
# Thanks and credit to Jesper Nygaard Schiøtt (jesper@schioett.dk) per http://autospinstaller.codeplex.com/Thread/View.aspx?ThreadId=237578 !

Function CreateWebAnalyticsApp([xml]$xmlinput)
{
	If ($($xmlinput.Configuration.ServiceApps.WebAnalyticsService.Provision) -eq $true) 
	{
		WriteLine
		try
		{
			$DBServer =  $xmlinput.Configuration.Farm.Database.DBServer
			$ApplicationPool = Get-HostedServicesAppPool ($xmlinput)
			$WebAnalyticsReportingDB = $DBPrefix+$xmlinput.Configuration.ServiceApps.WebAnalyticsService.ReportingDB
			$WebAnalyticsStagingDB = $DBPrefix+$xmlinput.Configuration.ServiceApps.WebAnalyticsService.StagingDB
			$WebAnalyticsServiceName = $xmlinput.Configuration.ServiceApps.WebAnalyticsService.Name
			$GetWebAnalyticsServiceApplication = Get-SPWebAnalyticsServiceApplication $WebAnalyticsServiceName -ea SilentlyContinue
			Write-Host -ForegroundColor White " - Provisioning $WebAnalyticsServiceName..."
	    	# Start Analytics service instances
			Write-Host -ForegroundColor White " - Checking Analytics Service instances..."
            $AnalyticsWebServiceInstances = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq "Microsoft.Office.Server.WebAnalytics.Administration.WebAnalyticsWebServiceInstance"}
            $AnalyticsWebServiceInstance = $AnalyticsWebServiceInstances | ? {$_.Server.Address -eq $env:COMPUTERNAME}
			If (-not $?) { throw " - Failed to find Analytics Web Service instance" }
			Write-Host -ForegroundColor White " - Starting local Analytics Web Service instance..."
	    	$AnalyticsWebServiceInstance.Provision()
			$AnalyticsDataProcessingInstances = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq "Microsoft.Office.Server.WebAnalytics.Administration.WebAnalyticsServiceInstance"}
			$AnalyticsDataProcessingInstance = $AnalyticsDataProcessingInstances | ? {$_.Server.Address -eq $env:COMPUTERNAME}
			If (-not $?) { throw " - Failed to find Analytics Data Processing Service instance" }
			UpdateProcessIdentity ($AnalyticsDataProcessingInstance)
			Write-Host -ForegroundColor White " - Starting local Analytics Data Processing Service instance..."
			$AnalyticsDataProcessingInstance.Provision()
			If ($GetWebAnalyticsServiceApplication -eq $null)
			{
				$StagerSubscription = "<StagingDatabases><StagingDatabase ServerName='$DBServer' DatabaseName='$WebAnalyticsStagingDB'/></StagingDatabases>"
				$WarehouseSubscription = "<ReportingDatabases><ReportingDatabase ServerName='$DBServer' DatabaseName='$WebAnalyticsReportingDB'/></ReportingDatabases>" 
				Write-Host -ForegroundColor White " - Creating $WebAnalyticsServiceName..."
		    	$ServiceApplication = New-SPWebAnalyticsServiceApplication -Name $WebAnalyticsServiceName -ReportingDataRetention 20 -SamplingRate 100 -ListOfReportingDatabases $WarehouseSubscription -ListOfStagingDatabases $StagerSubscription -ApplicationPool $ApplicationPool 
		    	# Create Web Analytics Service Application Proxy
				Write-Host -ForegroundColor White " - Creating $WebAnalyticsServiceName Proxy..."
				$NewWebAnalyticsServiceApplicationProxy = New-SPWebAnalyticsServiceApplicationProxy  -Name $WebAnalyticsServiceName -ServiceApplication $ServiceApplication.Name
			}
			Else {Write-Host -ForegroundColor White " - Web Analytics Service Application already provisioned."}
		}
		catch
		{
			Write-Output $_
		}
		WriteLine
	}
}
#EndRegion

#Region Create Secure Store Service Application
Function CreateSecureStoreServiceApp
{
    If ($($xmlinput.Configuration.ServiceApps.SecureStoreService.Provision) -eq $true) 
	{
		WriteLine
		try
		{
		    If (!($FarmPassphrase) -or ($FarmPassphrase -eq ""))
		    {
    			$FarmPassphrase = GetFarmPassPhrase ($xmlinput)
			}
			$SecureStoreServiceAppName = $xmlinput.Configuration.ServiceApps.SecureStoreService.Name
			$SecureStoreServiceAppProxyName = $xmlinput.Configuration.ServiceApps.SecureStoreService.ProxyName
			If ($SecureStoreServiceAppName -eq $null) {$SecureStoreServiceAppName = "State Service Application"}
			If ($SecureStoreServiceAppProxyName -eq $null) {$SecureStoreServiceAppProxyName = $SecureStoreServiceAppName}
			$SecureStoreDB = $DBPrefix+$xmlinput.Configuration.ServiceApps.SecureStoreService.Database
	        Write-Host -ForegroundColor White " - Provisioning Secure Store Service Application..."
			$ApplicationPool = Get-HostedServicesAppPool ($xmlinput)
			# Get the service instance
           	$SecureStoreServiceInstances = Get-SPServiceInstance | ? {$_.GetType().Equals([Microsoft.Office.SecureStoreService.Server.SecureStoreServiceInstance])}
			$SecureStoreServiceInstance = $SecureStoreServiceInstances | ? {$_.Server.Address -eq $env:COMPUTERNAME}
           	If (-not $?) { throw " - Failed to find Secure Store service instance" }
			# Start Service instance
        	If ($SecureStoreServiceInstance.Status -eq "Disabled")
			{ 
                Write-Host -ForegroundColor White " - Starting Secure Store Service Instance..."
            	$SecureStoreServiceInstance.Provision()
            	If (-not $?) { throw " - Failed to start Secure Store service instance" }
            	# Wait
		    	Write-Host -ForegroundColor Blue " - Waiting for Secure Store service..." -NoNewline
				While ($SecureStoreServiceInstance.Status -ne "Online") 
		    	{
					Write-Host -ForegroundColor Blue "." -NoNewline
					sleep 1
			    	$SecureStoreServiceInstances = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq "Microsoft.Office.SecureStoreService.Server.SecureStoreServiceInstance"}
					$SecureStoreServiceInstance = $SecureStoreServiceInstances | ? {$_.Server.Address -eq $env:COMPUTERNAME}
		    	}
				Write-Host -BackgroundColor Blue -ForegroundColor Black $($SecureStoreServiceInstance.Status)
        	}
			# Create Service Application
			$GetSPSecureStoreServiceApplication = Get-SPServiceApplication | ? {$_.GetType().Equals([Microsoft.Office.SecureStoreService.Server.SecureStoreServiceApplication])}
			If ($GetSPSecureStoreServiceApplication -eq $Null)
			{
				Write-Host -ForegroundColor White " - Creating Secure Store Service Application..."
				New-SPSecureStoreServiceApplication -Name $SecureStoreServiceAppName -PartitionMode:$false -Sharing:$false -DatabaseName $SecureStoreDB -ApplicationPool $($ApplicationPool.Name) -AuditingEnabled:$true -AuditLogMaxSize 30 | Out-Null
				Write-Host -ForegroundColor White " - Creating Secure Store Service Application Proxy..."
				Get-SPServiceApplication | ? {$_.GetType().Equals([Microsoft.Office.SecureStoreService.Server.SecureStoreServiceApplication])} | New-SPSecureStoreServiceApplicationProxy -Name $SecureStoreServiceAppProxyName -DefaultProxyGroup | Out-Null
				Write-Host -ForegroundColor White " - Done creating Secure Store Service Application."
			}
			Else {Write-Host -ForegroundColor White " - Secure Store Service Application already provisioned."}
			
			$secureStore = Get-SPServiceApplicationProxy | Where {$_.GetType().Equals([Microsoft.Office.SecureStoreService.Server.SecureStoreServiceApplicationProxy])} 
			Write-Host -ForegroundColor White " - Creating the Master Key..."
 			Update-SPSecureStoreMasterKey -ServiceApplicationProxy $secureStore.Id -Passphrase "$FarmPassPhrase"
			Write-Host -ForegroundColor White " - Creating the Application Key..."
			Update-SPSecureStoreApplicationServerKey -ServiceApplicationProxy $secureStore.Id -Passphrase "$FarmPassPhrase" -ErrorAction SilentlyContinue
			If (!$?)
			{
				# Try again...
				Write-Host -ForegroundColor White " - Creating the Application Key (2nd attempt)..."
				Update-SPSecureStoreApplicationServerKey -ServiceApplicationProxy $secureStore.Id -Passphrase "$FarmPassPhrase"
			}
		}
		catch
		{
			Write-Output $_
		}
		Write-Host -ForegroundColor White " - Done creating/configuring Secure Store Service Application."
		WriteLine
	}
}
#EndRegion

#Region Start Search Query and Site Settings Service
Function StartSearchQueryAndSiteSettingsService
{
	If ($($xmlinput.Configuration.Farm.Services.SearchQueryAndSiteSettingsService.Start) -eq $true)
	{
		WriteLine
		try
		{
			# Get the service instance
		    $SearchQueryAndSiteSettingsServices = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq "Microsoft.Office.Server.Search.Administration.SearchQueryAndSiteSettingsServiceInstance"}
			$SearchQueryAndSiteSettingsService = $SearchQueryAndSiteSettingsServices | ? {$_.Server.Address -eq $env:COMPUTERNAME}
		    If (-not $?) { throw " - Failed to find Search Query and Site Settings service instance" }
		    # Start Service instance
   		 	Write-Host -ForegroundColor White " - Starting Search Query and Site Settings Service Instance..."
			If($SearchQueryAndSiteSettingsService.Status -eq "Disabled")
			{ 
			    $SearchQueryAndSiteSettingsService.Provision()
        		If (-not $?) { throw " - Failed to start Search Query and Site Settings service instance" }
        		# Wait
    			Write-Host -ForegroundColor Blue " - Waiting for Search Query and Site Settings service..." -NoNewline
				While ($SearchQueryAndSiteSettingsService.Status -ne "Online") 
	    		{
					Write-Host -ForegroundColor Blue "." -NoNewline
		  			start-sleep 1
				    $SearchQueryAndSiteSettingsServices = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq "Microsoft.Office.Server.Search.Administration.SearchQueryAndSiteSettingsServiceInstance"}
		  			$SearchQueryAndSiteSettingsService = $SearchQueryAndSiteSettingsServices | ? {$_.Server.Address -eq $env:COMPUTERNAME}
	    		}
				Write-Host -BackgroundColor Blue -ForegroundColor Black $($SearchQueryAndSiteSettingsService.Status)
    		}
    		Else {Write-Host -ForegroundColor White " - Search Query and Site Settings Service already started."}
		}
		catch
		{
			Write-Output $_ 
		}
		WriteLine
	}
}
#EndRegion

#Region Stop Foundation Web Service
# ===================================================================================
# Func: StopFoundationWebService
# Desc: Disables the Microsoft SharePoint Foundation Web Application service instance (for App servers)
# ===================================================================================
Function StopFoundationWebService
{
	$FoundationWebServices = Get-SPServiceInstance | ? {$_.Service.ToString() -eq "SPWebService"}
	$FoundationWebService = $FoundationWebServices | ? {$_.Server.Address -eq $env:COMPUTERNAME}
	Write-Host -ForegroundColor White " - Stopping $($FoundationWebService.TypeName)..."
	$FoundationWebService.Unprovision()
   	If (-not $?) {Throw " - Failed to stop $($FoundationWebService.TypeName)" }
    # Wait
	Write-Host -ForegroundColor Blue " - Waiting for $($FoundationWebService.TypeName) to stop..." -NoNewline
	While ($FoundationWebService.Status -ne "Disabled") 
	{
		Write-Host -ForegroundColor Blue "." -NoNewline
		sleep 1
		$FoundationWebServices = Get-SPServiceInstance | ? {$_.Service.ToString() -eq "SPWebService"}
		$FoundationWebService = $FoundationWebServices | ? {$_.Server.Address -eq $env:COMPUTERNAME}
	}
	Write-Host -BackgroundColor Blue -ForegroundColor Black $($FoundationWebService.Status)
}
#EndRegion

#Region Stop Workflow Timer Service
# ===================================================================================
# Func: StopWorkflowTimerService
# Desc: Disables the Microsoft SharePoint Foundation Workflow Timer Service
# ===================================================================================
Function StopWorkflowTimerService
{
	$WorkflowTimerServices = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq "Microsoft.SharePoint.Workflow.SPWorkflowTimerServiceInstance"}
	$WorkflowTimerService = $WorkflowTimerServices | ? {$_.Server.Address -eq $env:COMPUTERNAME}
	Write-Host -ForegroundColor White " - Stopping $($WorkflowTimerService.TypeName)..."
	$WorkflowTimerService.Unprovision()
   	If (-not $?) {Throw " - Failed to stop $($WorkflowTimerService.TypeName)" }
    # Wait
	Write-Host -ForegroundColor Blue " - Waiting for $($WorkflowTimerService.TypeName) to stop..." -NoNewline
	While ($WorkflowTimerService.Status -ne "Disabled") 
	{
		Write-Host -ForegroundColor Blue "." -NoNewline
		sleep 1
		$WorkflowTimerServices = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq "Microsoft.SharePoint.Workflow.SPWorkflowTimerServiceInstance"}
		$WorkflowTimerService = $WorkflowTimerServices | ? {$_.Server.Address -eq $env:COMPUTERNAME}
	}
	Write-Host -BackgroundColor Blue -ForegroundColor Black $($WorkflowTimerService.Status)
}
#EndRegion

#Region Configure Foundation Search
# ====================================================================================
# Func: ConfigureFoundationSearch
# Desc: Updates the service account for SPSearch4 (SharePoint Foundation (Help) Search)
# ====================================================================================

Function ConfigureFoundationSearch ([xml]$xmlinput)
# Does not actually provision Foundation Search as of yet, just updates the service account it would run under to mitigate Health Analyzer warnings
{
    WriteLine
	Try
	{
		$FoundationSearchService = (Get-SPFarm).Services | where {$_.Name -eq "SPSearch4"}
		$spservice = Get-spserviceaccountxml $xmlinput
		$ManagedAccountGen = Get-SPManagedAccount | Where-Object {$_.UserName -eq $($spservice.username)}
		Write-Host -ForegroundColor White " - Applying service account $($spservice.username) to service SPSearch4..."
        $FoundationSearchService.ProcessIdentity.CurrentIdentityType = "SpecificUser"
        $FoundationSearchService.ProcessIdentity.ManagedAccount = $ManagedAccountGen
        $FoundationSearchService.ProcessIdentity.Update()
        $FoundationSearchService.ProcessIdentity.Deploy()
        $FoundationSearchService.Update()
 		Write-Host -ForegroundColor White " - Done."
	}
	Catch
	{
		$_
		Write-Warning " - An error occurred updating the service account for SPSearch4."
	}
	WriteLine
}
#EndRegion

#Region Configure SPTraceV4 (Logging)
# ====================================================================================
# Func: ConfigureTracing
# Desc: Updates the service account for SPTraceV4 (SharePoint Foundation (Help) Search)
# ====================================================================================

Function ConfigureTracing ([xml]$xmlinput)
{
	WriteLine
	$spservice = Get-spserviceaccountxml $xmlinput
	$SPTraceV4 = (Get-SPFarm).Services | where {$_.Name -eq "SPTraceV4"}
    $AppPoolAcctDomain,$AppPoolAcctUser = $spservice.username -Split "\\"
    Write-Host -ForegroundColor White " - Applying service account $($spservice.username) to service SPTraceV4..."
	#Add to Performance Monitor Users group
    Write-Host -ForegroundColor White " - Adding $($spservice.username) to local Performance Monitor Users group..."
    Try
  	{
   		([ADSI]"WinNT://$env:COMPUTERNAME/Performance Monitor Users,group").Add("WinNT://$AppPoolAcctDomain/$AppPoolAcctUser")
        If (-not $?) {throw}
   	}
    Catch 
    {
        Write-Host -ForegroundColor White " - $($spservice.username) is already a member of Performance Monitor Users."
    }
    #Add to Performance Log Users group
    Write-Host -ForegroundColor White " - Adding $($spservice.username) to local Performance Log Users group..."
    Try
  	{
   		([ADSI]"WinNT://$env:COMPUTERNAME/Performance Log Users,group").Add("WinNT://$AppPoolAcctDomain/$AppPoolAcctUser")
        If (-not $?) {throw}
   	}
    Catch 
    {
        Write-Host -ForegroundColor White " - $($spservice.username) is already a member of Performance Log Users."
    }
	$ManagedAccountGen = Get-SPManagedAccount | Where-Object {$_.UserName -eq $($spservice.username)}
	Try
	{
		Write-Host -ForegroundColor White " - Updating service account..."
		$SPTraceV4.ProcessIdentity.CurrentIdentityType = "SpecificUser"
    	$SPTraceV4.ProcessIdentity.ManagedAccount = $ManagedAccountGen
    	$SPTraceV4.ProcessIdentity.Update()
    	$SPTraceV4.ProcessIdentity.Deploy()
    	$SPTraceV4.Update()
		Write-Host -ForegroundColor White " - Restarting service SPTraceV4..."
		Restart-Service -Name "SPTraceV4"
		Write-Host -ForegroundColor White " - Done."
	}
	Catch
	{
		$_
		Write-Warning " - An error occurred updating the service account for service SPTraceV4."
	}
	WriteLine
}
#EndRegion

#Region Provision Enterprise Search

# Original script for SharePoint 2010 beta2 by Gary Lapointe ()
# 
# Modified by Søren Laurits Nielsen (soerennielsen.wordpress.com):
# 
# Modified to fix some errors since some cmdlets have changed a bit since beta 2 and added support for "ShareName" for 
# the query component. It is required for non DC computers. 
# 
# Modified to support "localhost" moniker in config file. 
# 
# Note: Accounts, Shares and directories specified in the config file must be setup beforehand.

function CreateEnterpriseSearchServiceApp([xml]$xmlinput)
{
	If ($($xmlinput.Configuration.ServiceApps.EnterpriseSearchService.Provision) -eq $true)
	{
	WriteLine
	Write-Host -ForegroundColor White " - Provisioning Enterprise Search..."
	# SLN: Added support for local host
    $svcConfig = $xmlinput.Configuration.ServiceApps.EnterpriseSearchService
	$PortalWebApp = $xmlinput.Configuration.WebApplications.WebApplication | Where {$_.Type -eq "Portal"}
	$PortalURL = $PortalWebApp.URL
	$PortalPort = $PortalWebApp.Port
	$MySiteWebApp = $xmlinput.Configuration.WebApplications.WebApplication | Where {$_.Type -eq "MySiteHost"}
	$MySiteURL = $MySiteWebApp.URL
	$MySitePort = $MySiteWebApp.Port
    If ($MySiteURL -like "https://*") {$MySiteHostHeader = $MySiteURL -replace "https://",""}        
    Else {$MySiteHostHeader = $MySiteURL -replace "http://",""}
	$secSearchServicePassword = ConvertTo-SecureString -String $svcConfig.Password -AsPlainText -Force
	$secContentAccessAcctPWD = ConvertTo-SecureString -String $svcConfig.EnterpriseSearchServiceApplications.EnterpriseSearchServiceApplication.ContentAccessAccountPWD -AsPlainText -Force

    $searchSvc = Get-SPEnterpriseSearchServiceInstance -Local
    If ($searchSvc -eq $null) {
        throw " - Unable to retrieve search service."
    }

    Get-SPEnterpriseSearchService | Set-SPEnterpriseSearchService  `
      -ContactEmail $svcConfig.ContactEmail -ConnectionTimeout $svcConfig.ConnectionTimeout `
      -AcknowledgementTimeout $svcConfig.AcknowledgementTimeout -ProxyType $svcConfig.ProxyType `
      -IgnoreSSLWarnings $svcConfig.IgnoreSSLWarnings -InternetIdentity $svcConfig.InternetIdentity -PerformanceLevel $svcConfig.PerformanceLevel `
	  -ServiceAccount $svcConfig.Account -ServicePassword $secSearchServicePassword

	Write-Host -ForegroundColor White " - Setting default index location on search service..."
    $searchSvc | Set-SPEnterpriseSearchServiceInstance -DefaultIndexLocation $svcConfig.IndexLocation -ErrorAction SilentlyContinue -ErrorVariable err

    $svcConfig.EnterpriseSearchServiceApplications.EnterpriseSearchServiceApplication | ForEach-Object {
        $appConfig = $_
		If (($appConfig.DatabaseServer -ne "") -and ($appConfig.DatabaseServer -ne $null))
		{
			$DBServer = $appConfig.DatabaseServer
		}
		Else
		{
			$DBServer =  $xmlinput.Configuration.Farm.Database.DBServer
		}

        # Try and get the application pool if it already exists
        $pool = Get-ApplicationPool $appConfig.ApplicationPool
        $adminPool = Get-ApplicationPool $appConfig.AdminComponent.ApplicationPool

        $searchApp = Get-SPEnterpriseSearchServiceApplication -Identity $appConfig.Name -ErrorAction SilentlyContinue

        If ($searchApp -eq $null) {
            Write-Host -ForegroundColor White " - Creating $($appConfig.Name)..."
            $searchApp = New-SPEnterpriseSearchServiceApplication -Name $appConfig.Name `
                -DatabaseServer $DBServer `
                -DatabaseName $($DBPrefix+$appConfig.DatabaseName) `
                -FailoverDatabaseServer $appConfig.FailoverDatabaseServer `
                -ApplicationPool $pool `
                -AdminApplicationPool $adminPool `
                -Partitioned:([bool]::Parse($appConfig.Partitioned)) `
                -SearchApplicationType $appConfig.SearchServiceApplicationType
        } else {
            Write-Host -ForegroundColor White " - Enterprise search service application already exists, skipping creation."
        }
		
        $installCrawlSvc = (($appConfig.CrawlServers.Server | where {$_.Name -eq $env:computername}) -ne $null)
        $installQuerySvc = (($appConfig.QueryServers.Server | where {$_.Name -eq $env:computername}) -ne $null)
        $installAdminCmpnt = (($appConfig.AdminComponent.Server | where {$_.Name -eq $env:computername}) -ne $null)
        $installSyncSvc = (($appConfig.SearchQueryAndSiteSettingsServers.Server | where {$_.Name -eq $env:computername}) -ne $null)

        If ($searchSvc.Status -ne "Online" -and ($installCrawlSvc -or $installQuerySvc)) {
            $searchSvc | Start-SPEnterpriseSearchServiceInstance
        }

        If ($installAdminCmpnt) {
            Write-Host -ForegroundColor White " - Setting administration component..."
            Set-SPEnterpriseSearchAdministrationComponent -SearchApplication $searchApp -SearchServiceInstance $searchSvc
        
			$AdminCmpnt = $searchApp | Get-SPEnterpriseSearchAdministrationComponent
			If ($AdminCmpnt.Initialized -eq $false)
			{
				Write-Host -ForegroundColor Blue " - Waiting for administration component initialization..." -NoNewline
				While ($AdminCmpnt.Initialized -ne $true)
				{
					Write-Host -ForegroundColor Blue "." -NoNewline
  					start-sleep 1
					$AdminCmpnt = $searchApp | Get-SPEnterpriseSearchAdministrationComponent
				}
				Write-Host -BackgroundColor Blue -ForegroundColor Black $($AdminCmpnt.Initialized)
			}
			Else {Write-Host -ForegroundColor White " - Administration component already initialized."}
		}
		
		Write-Host -ForegroundColor White " - Setting content access account for $($appconfig.Name)..."
		$searchApp | Set-SPEnterpriseSearchServiceApplication -DefaultContentAccessAccountName $svcConfig.EnterpriseSearchServiceApplications.EnterpriseSearchServiceApplication.ContentAccessAccount `
												 			  -DefaultContentAccessAccountPassword $secContentAccessAcctPWD

        $crawlTopology = Get-SPEnterpriseSearchCrawlTopology -SearchApplication $searchApp | where {$_.CrawlComponents.Count -gt 0 -or $_.State -eq "Inactive"}

        If ($crawlTopology -eq $null) {
            Write-Host -ForegroundColor White " - Creating new crawl topology..."
            $crawlTopology = $searchApp | New-SPEnterpriseSearchCrawlTopology
        } else {
            Write-Host -ForegroundColor White " - A crawl topology with crawl components already exists, skipping crawl topology creation."
        }
 
        If ($installCrawlSvc) {
            $crawlComponent = $crawlTopology.CrawlComponents | where {$_.ServerName -eq $env:ComputerName}
            If ($crawlTopology.CrawlComponents.Count -eq 0 -and $crawlComponent -eq $null) {
                $crawlStore = $searchApp.CrawlStores | where {$_.Name -eq "$($DBPrefix+$appConfig.DatabaseName)_CrawlStore"}
                Write-Host -ForegroundColor White " - Creating new crawl component..."
                $crawlComponent = New-SPEnterpriseSearchCrawlComponent -SearchServiceInstance $searchSvc -SearchApplication $searchApp -CrawlTopology $crawlTopology -CrawlDatabase $crawlStore.Id.ToString() -IndexLocation $appConfig.IndexLocation
            } else {
                Write-Host -ForegroundColor White " - Crawl component already exist, skipping crawl component creation."
            }
        }

        $queryTopology = Get-SPEnterpriseSearchQueryTopology -SearchApplication $searchApp | where {$_.QueryComponents.Count -gt 0 -or $_.State -eq "Inactive"}

        If ($queryTopology -eq $null) {
            Write-Host -ForegroundColor White " - Creating new query topology..."
            $queryTopology = $searchApp | New-SPEnterpriseSearchQueryTopology -Partitions $appConfig.Partitions
        } else {
            Write-Host -ForegroundColor White " - A query topology with query components already exists, skipping query topology creation."
        }

        If ($installQuerySvc) {
            $queryComponent = $queryTopology.QueryComponents | where {$_.ServerName -eq $env:ComputerName}
            #If ($true){ #$queryTopology.QueryComponents.Count -eq 0 -and $queryComponent -eq $null) {
            If ($queryTopology.QueryComponents.Count -eq 0 -and $queryComponent -eq $null) {
                $partition = ($queryTopology | Get-SPEnterpriseSearchIndexPartition)
                Write-Host -ForegroundColor White " - Creating new query component..."
                $queryComponent = New-SPEnterpriseSearchQueryComponent -IndexPartition $partition -QueryTopology $queryTopology -SearchServiceInstance $searchSvc -ShareName $svcConfig.ShareName
                Write-Host -ForegroundColor White " - Setting index partition and property store database..."
                $propertyStore = $searchApp.PropertyStores | where {$_.Name -eq "$($DBPrefix+$appConfig.DatabaseName)_PropertyStore"}
                $partition | Set-SPEnterpriseSearchIndexPartition -PropertyDatabase $propertyStore.Id.ToString()
            } else {
                Write-Host -ForegroundColor White " - Query component already exist, skipping query component creation."
            }
        }

        If ($installSyncSvc) {            
            # SLN: Updated to new syntax
			$SearchQueryAndSiteSettingsService = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq "Microsoft.Office.Server.Search.Administration.SearchQueryAndSiteSettingsServiceInstance"}
    		If (-not $?) { throw " - Failed to find Search Query and Site Settings service instance" }
			# Start Service instance
    		If ($SearchQueryAndSiteSettingsService.Status -eq "Disabled")
			{
   	    		Write-Host -ForegroundColor White " - Starting Search Query and Site Settings Service Instance..."
				Start-SPServiceInstance (Get-SPServiceInstance | where { $_.TypeName -eq "Search Query and Site Settings Service"}).Id | Out-Null
				Write-Host -ForegroundColor Blue " - Waiting for Search Query and Site Settings service..." -NoNewline
				While ($SearchQueryAndSiteSettingsService.Status -ne "Online") 
	    		{
					Write-Host -ForegroundColor Blue "." -NoNewline
		  			start-sleep 1
					$SearchQueryAndSiteSettingsService = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq "Microsoft.Office.Server.Search.Administration.SearchQueryAndSiteSettingsServiceInstance"}
	    		}
				Write-Host -BackgroundColor Blue -ForegroundColor Black $($SearchQueryAndSiteSettingsService.Status)
    		}
    		Else {Write-Host -ForegroundColor White " - Search Query and Site Settings Service already started."}
			}
        

        # Don't activate until we've added all components
        $allCrawlServersDone = $true
        $appConfig.CrawlServers.Server | ForEach-Object {
            $server = $_.Name
            $top = $crawlTopology.CrawlComponents | where {$_.ServerName -eq $server}
            If ($top -eq $null) { $allCrawlServersDone = $false }
        }

        If ($allCrawlServersDone -and $crawlTopology.State -ne "Active") {
            Write-Host -ForegroundColor White " - Setting new crawl topology to active..."
            $crawlTopology | Set-SPEnterpriseSearchCrawlTopology -Active -Confirm:$false
			Write-Host -ForegroundColor Blue " - Waiting for Crawl Components..." -NoNewLine
			while ($true) 
			{
				$ct = Get-SPEnterpriseSearchCrawlTopology -Identity $crawlTopology -SearchApplication $searchApp
				$state = $ct.CrawlComponents | where {$_.State -ne "Ready"}
				If ($ct.State -eq "Active" -and $state -eq $null) 
				{
					break
				}
				Write-Host -ForegroundColor Blue "." -NoNewLine
				Start-Sleep 1
			}
            Write-Host -BackgroundColor Blue -ForegroundColor Black $($crawlTopology.State)

			# Need to delete the original crawl topology that was created by default
            $searchApp | Get-SPEnterpriseSearchCrawlTopology | where {$_.State -eq "Inactive"} | Remove-SPEnterpriseSearchCrawlTopology -Confirm:$false
        }

        $allQueryServersDone = $true
        $appConfig.QueryServers.Server | ForEach-Object {
            $server = $_.Name
            $top = $queryTopology.QueryComponents | where {$_.ServerName -eq $server}
            If ($top -eq $null) { $allQueryServersDone = $false }
        }

        # Make sure we have a crawl component added and started before trying to enable the query component
        If ($allCrawlServersDone -and $allQueryServersDone -and $queryTopology.State -ne "Active") {
            Write-Host -ForegroundColor White " - Setting query topology as active..."
            $queryTopology | Set-SPEnterpriseSearchQueryTopology -Active -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable err
			Write-Host -ForegroundColor Blue " - Waiting for Query Components..." -NoNewLine
			while ($true) 
			{
				$qt = Get-SPEnterpriseSearchQueryTopology -Identity $queryTopology -SearchApplication $searchApp
				$state = $qt.QueryComponents | where {$_.State -ne "Ready"}
				If ($qt.State -eq "Active" -and $state -eq $null) 
				{
				break
				}
				Write-Host -ForegroundColor Blue "." -NoNewLine
				Start-Sleep 1
			}
            Write-Host -BackgroundColor Blue -ForegroundColor Black $($queryTopology.State)
			
            # Need to delete the original query topology that was created by default
            $searchApp | Get-SPEnterpriseSearchQueryTopology | where {$_.State -eq "Inactive"} | Remove-SPEnterpriseSearchQueryTopology -Confirm:$false
        }

        $proxy = Get-SPEnterpriseSearchServiceApplicationProxy -Identity $appConfig.Proxy.Name -ErrorAction SilentlyContinue
        If ($proxy -eq $null) {
            Write-Host -ForegroundColor White " - Creating enterprise search service application proxy..."
            $proxy = New-SPEnterpriseSearchServiceApplicationProxy -Name $appConfig.Proxy.Name -SearchApplication $searchApp -Partitioned:([bool]::Parse($appConfig.Proxy.Partitioned))
        } else {
            Write-Host -ForegroundColor White " - Enterprise search service application proxy already exists, skipping creation."
        }

        If ($proxy.Status -ne "Online") {
            $proxy.Status = "Online"
            $proxy.Update()
        }

        $proxy | Set-ProxyGroupsMembership $appConfig.Proxy.ProxyGroup
    }

    # SLN: Create the network share (will report an error if exist)
    # default to primitives 
    $PathToShare = """" + $svcConfig.ShareName + "=" + $svcConfig.IndexLocation + """"
	# The path to be shared should exist if the Enterprise Search App creation succeeded earlier
    Write-Host -ForegroundColor White " - Creating network share $PathToShare"
    net share $PathToShare "/GRANT:WSS_WPG,CHANGE"

	# Set the crawl start addresses (including the elusive sps3:// URL required for People Search, if My Sites are provisioned)
	$CrawlStartAddresses = $PortalURL+":"+$PortalPort
	If ($MySiteURL -and $MySitePort -and $MySiteHostHeader)
	{	
		# Need to set the correct sps (People Search) URL protocol in case My Sites are SSL-bound
		If ($MySiteURL -like "https*") {$PeopleSearchProtocol = "sps3s://"}
		Else {$PeopleSearchProtocol = "sps3://"}
		$CrawlStartAddresses += ","+$MySiteURL+":"+$MySitePort+","+$PeopleSearchProtocol+$MySiteHostHeader+":"+$MySitePort
	}
	Get-SPEnterpriseSearchServiceApplication | Get-SPEnterpriseSearchCrawlContentSource | Set-SPEnterpriseSearchCrawlContentSource -StartAddresses $CrawlStartAddresses
	
	WriteLine
	}
	Else
	{
		WriteLine
		#Set the service account to something other than Local System to avoid Health Analyzer warnings
	    $svcConfig = $xmlinput.Configuration.ServiceApps.EnterpriseSearchService
		$secSearchServicePassword = ConvertTo-SecureString -String $svcConfig.Password -AsPlainText -Force
		If (($svcConfig.Account) -and ($secSearchServicePassword))
		{
    		# Use the values for Search Service account and password, if they've been defined
			$username = $svcConfig.Account
			$password = $secSearchServicePassword
		}
		Else
		{
			$spservice = $xmlinput.Configuration.Farm.ManagedAccounts.ManagedAccount | Where-Object { $_.CommonName -match "spservice" }
			$username = $spservice.username
			$password =  ConvertTo-SecureString "$($spservice.password)" –AsPlaintext –Force
		}
		Write-Host -ForegroundColor White " - Applying service account $username to Search Service..."
		Get-SPEnterpriseSearchService | Set-SPEnterpriseSearchService -ServiceAccount $username -ServicePassword $password
		If (!$?) {Write-Error " - An error occurred setting the Search Service account!"}
		WriteLine
	}
}

function Set-ProxyGroupsMembership([System.Xml.XmlElement[]]$groups, [Microsoft.SharePoint.Administration.SPServiceApplicationProxy[]]$InputObject)
{
    begin {}
    process {
        $proxy = $_
        
        # Clear any existing proxy group assignments
        Get-SPServiceApplicationProxyGroup | where {$_.Proxies -contains $proxy} | ForEach-Object {
            $proxyGroupName = $_.Name
            If ([string]::IsNullOrEmpty($proxyGroupName)) { $proxyGroupName = "Default" }
            $group = $null
            [bool]$matchFound = $false
            foreach ($g in $groups) {
                $group = $g.Name
                If ($group -eq $proxyGroupName) { 
                    $matchFound = $true
                    break 
                }
            }
            If (!$matchFound) {
                Write-Host -ForegroundColor White " - Removing ""$($proxy.DisplayName)"" from ""$proxyGroupName"""
                $_ | Remove-SPServiceApplicationProxyGroupMember -Member $proxy -Confirm:$false -ErrorAction SilentlyContinue
            }
        }
        
        foreach ($g in $groups) {
            $group = $g.Name

            $pg = $null
            If ($group -eq "Default" -or [string]::IsNullOrEmpty($group)) {
                $pg = [Microsoft.SharePoint.Administration.SPServiceApplicationProxyGroup]::Default
            } else {
                $pg = Get-SPServiceApplicationProxyGroup $group -ErrorAction SilentlyContinue -ErrorVariable err
                If ($pg -eq $null) {
                    $pg = New-SPServiceApplicationProxyGroup -Name $name
                }
            }
            
            $pg = $pg | where {$_.Proxies -notcontains $proxy}
            If ($pg -ne $null) { 
                Write-Host -ForegroundColor White " - Adding ""$($proxy.DisplayName)"" to ""$($pg.DisplayName)"""
                $pg | Add-SPServiceApplicationProxyGroupMember -Member $proxy 
            }
        }
    }
    end {}
}

function Get-ApplicationPool([System.Xml.XmlElement]$appPoolConfig) {
    # Try and get the application pool if it already exists
    # SLN: Updated names
    $pool = Get-SPServiceApplicationPool -Identity $appPoolConfig.Name -ErrorVariable err -ErrorAction SilentlyContinue
    If ($err) {
        # The application pool does not exist so create.
        Write-Host -ForegroundColor White " - Getting $($appPoolConfig.Account) account for application pool..."
        $ManagedAccountSearch = (Get-SPManagedAccount -Identity $appPoolConfig.Account -ErrorVariable err -ErrorAction SilentlyContinue)
        If ($err) {
            If (($appPoolConfig.Password -ne "") -and ($appPoolConfig.Password -ne $null)) 
			{
				$appPoolConfigPWD = (ConvertTo-SecureString $appPoolConfig.Password -AsPlainText -force)
				$accountCred = New-Object System.Management.Automation.PsCredential $appPoolConfig.Account,$appPoolConfigPWD
			}
			Else
			{
				$accountCred = Get-Credential $appPoolConfig.Account
			}
            $ManagedAccountSearch = New-SPManagedAccount -Credential $accountCred
        }
        Write-Host -ForegroundColor White " - Creating $($appPoolConfig.Name)..."
        $pool = New-SPServiceApplicationPool -Name $($appPoolConfig.Name) -Account $ManagedAccountSearch
    }
    return $pool
}

#EndRegion

#Region Create Business Data Catalog Service Application
# ===================================================================================
# Func: CreateBusinessDataConnectivityServiceApp
# Desc: Business Data Catalog Service Application
# From: http://autospinstaller.codeplex.com/discussions/246532 (user bunbunaz)
# ===================================================================================
Function CreateBusinessDataConnectivityServiceApp([xml]$xmlinput)
{
    If ($($xmlinput.Configuration.ServiceApps.BusinessDataConnectivity.Provision) -eq $true) 
    {
		WriteLine
	 	Try
     	{
   			$DBServer =  $xmlinput.Configuration.Farm.Database.DBServer
			$BdcAppName = $xmlinput.Configuration.ServiceApps.BusinessDataConnectivity.Name
   			$BdcDataDB = $DBPrefix+$($xmlinput.Configuration.ServiceApps.BusinessDataConnectivity.Database)
			$BdcAppProxyName = $xmlinput.Configuration.ServiceApps.BusinessDataConnectivity.ProxyName
   			Write-Host -ForegroundColor White " - Provisioning $BdcAppName"
			$ApplicationPool = Get-HostedServicesAppPool ($xmlinput)
			Write-Host -ForegroundColor White " - Checking local service instance..."
   			# Get the service instance
   			$BdcServiceInstances = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq "Microsoft.SharePoint.BusinessData.SharedService.BdcServiceInstance"}
            $BdcServiceInstance = $BdcServiceInstances | ? {$_.Server.Address -eq $env:COMPUTERNAME}
   			If (-not $?) { throw " - Failed to find the service instance" }
   			# Start Service instances
   			If($BdcServiceInstance.Status -eq "Disabled")
     		{ 
             	Write-Host -ForegroundColor White " - Starting $($BdcServiceInstance.TypeName)..."
                $BdcServiceInstance.Provision()
                If (-not $?) { throw " - Failed to start $($BdcServiceInstance.TypeName)" }
    			# Wait
       			Write-Host -ForegroundColor Blue " - Waiting for $($BdcServiceInstance.TypeName)..." -NoNewline
       			While ($BdcServiceInstance.Status -ne "Online") 
       			{
        			Write-Host -ForegroundColor Blue "." -NoNewline
        			sleep 1
        			$BdcServiceInstances = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq "Microsoft.SharePoint.BusinessData.SharedService.BdcServiceInstance"}
     				$BdcServiceInstance = $BdcServiceInstances | ? {$_.Server.Address -eq $env:COMPUTERNAME}
       			}
       			Write-Host -BackgroundColor Blue -ForegroundColor Black ($BdcServiceInstance.Status)
   			}
   			Else 
   			{
    			Write-Host -ForegroundColor White " - $($BdcServiceInstance.TypeName) already started."
   			}
          	# Create a Business Data Catalog Service Application 
   			If ((Get-SPServiceApplication | ? {$_.GetType().ToString() -eq "Microsoft.SharePoint.BusinessData.SharedService.BdcServiceApplication"}) -eq $null)
        	{      
       			# Create Service App
          		Write-Host -ForegroundColor White " - Creating $BdcAppName..."   
    			$BdcDataServiceApp = New-SPBusinessDataCatalogServiceApplication -Name $BdcAppName -ApplicationPool $ApplicationPool -DatabaseServer $DBServer -DatabaseName $BdcDataDB
    			If (-not $?) { throw " - Failed to create $BdcAppName" }
    			### Get the default proxy which was just created and remove it and its data
    			##Write-Host -ForegroundColor White " - Removing the default service application proxy..."
       			##$BdcServiceAppProxy = Get-SPServiceApplicationProxy | ? {$_.TypeName -eq "Business Data Connectivity Service Application Proxy"}
       			##$BdcServiceAppProxyID = $BdcServiceAppProxy.Id
    			##Write-Host -ForegroundColor White " - Default service application proxy    =$BdcServiceAppProxy"
    			##Write-Host -ForegroundColor White " - Default service application proxy ID =$BdcServiceAppProxyID"
    			##Remove-SPServiceApplicationProxy $BdcServiceAppProxyID -RemoveData -Confirm:$false
				### Create new proxy
       			##Write-Host -ForegroundColor White " - Creating $BdcAppName Proxy..."
                ##$BdcDataServiceAppProxy  = New-SPBusinessDataCatalogServiceApplicationProxy -Name "$BdcAppName Proxy" -ServiceApplication $BdcDataServiceApp -DefaultProxyGroup
                ##If (-not $?) { throw " - Failed to create $BdcAppName Proxy" }
           	}
        	Else 
   			{
    			Write-Host -ForegroundColor White " - $BdcAppName already provisioned."
   			}
   			Write-Host -ForegroundColor White " - Done creating $BdcAppName."
     	}
     	catch
     	{
     	 	Write-Output $_ 
     	}
	 	WriteLine
    }
}
#EndRegion

#Region Create Excel Service
Function CreateExcelServiceApp ([xml]$xmlinput)
{
    If ($($xmlinput.Configuration.EnterpriseServiceApps.ExcelServices.Provision) -eq $true)
	{
		Try
	 	{
			WriteLine
			$ExcelAppName = $xmlinput.Configuration.EnterpriseServiceApps.ExcelServices.Name
			$PortalWebApp = $xmlinput.Configuration.WebApplications.WebApplication | Where {$_.Type -eq "Portal"}
			$PortalURL = $PortalWebApp.URL
			$PortalPort = $PortalWebApp.Port
			Write-Host -ForegroundColor White " - Provisioning $ExcelAppName..."
			$ApplicationPool = Get-HostedServicesAppPool ($xmlinput)
			Write-Host -ForegroundColor White " - Checking local service instance..."
   			# Get the service instance
   			$ExcelServiceInstances = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq "Microsoft.Office.Excel.Server.MossHost.ExcelServerWebServiceInstance"}
            $ExcelServiceInstance = $ExcelServiceInstances | ? {$_.Server.Address -eq $env:COMPUTERNAME}
   			If (-not $?) { throw " - Failed to find the service instance" }
   			# Start Service instances
   			If($ExcelServiceInstance.Status -eq "Disabled")
     		{ 
             	Write-Host -ForegroundColor White " - Starting $($ExcelServiceInstance.TypeName)..."
                $ExcelServiceInstance.Provision()
                If (-not $?) { throw " - Failed to start $($ExcelServiceInstance.TypeName) instance" }
    			# Wait
       			Write-Host -ForegroundColor Blue " - Waiting for $($ExcelServiceInstance.TypeName)..." -NoNewline
       			While ($ExcelServiceInstance.Status -ne "Online") 
       			{
        			Write-Host -ForegroundColor Blue "." -NoNewline
        			sleep 1
        			$ExcelServiceInstances = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq "Microsoft.Office.Excel.Server.MossHost.ExcelServerWebServiceInstance"}
     				$ExcelServiceInstance = $ExcelServiceInstances | ? {$_.Server.Address -eq $env:COMPUTERNAME}
       			}
       			Write-Host -BackgroundColor Blue -ForegroundColor Black ($ExcelServiceInstance.Status)
   			}
   			Else 
   			{
    			Write-Host -ForegroundColor White " - $($ExcelServiceInstance.TypeName) already started."
   			}
          	# Create an Excel Service Application 
   			If ((Get-SPServiceApplication | ? {$_.GetType().ToString() -eq "Microsoft.Office.Excel.Server.MossHost.ExcelServerWebServiceApplication"}) -eq $null)
        	{      
       			# Create Service App
          		Write-Host -ForegroundColor White " - Creating $ExcelAppName..."
				# Check if our new cmdlets are available yet,  if not, re-load the SharePoint PS Snapin
				If (!(Get-Command New-SPExcelServiceApplication -ErrorAction SilentlyContinue))
				{
					Write-Host -ForegroundColor White " - Re-importing SP PowerShell Snapin to enable new cmdlets..."
					Remove-PSSnapin Microsoft.SharePoint.PowerShell
					Load-SharePoint-Powershell
				}
    			$ExcelServiceApp = New-SPExcelServiceApplication -name $ExcelAppName –ApplicationPool $($ApplicationPool.Name) –Default
    			If (-not $?) { throw " - Failed to create $ExcelAppName" }
				Write-Host -ForegroundColor White " - Configuring service app settings..."
				Set-SPExcelFileLocation -Identity "http://" -LocationType SharePoint -IncludeChildren -Address $PortalURL`:$PortalPort -ExcelServiceApplication $ExcelAppName -ExternalDataAllowed 2 -WorkbookSizeMax 10
           	}
        	Else 
   			{
    			Write-Host -ForegroundColor White " - $ExcelAppName already provisioned."
   			}
   			Write-Host -ForegroundColor White " - Done creating $ExcelAppName."
		}
		Catch
	 	{
	  		Write-Output $_
	 	}
		WriteLine
	}
}
#EndRegion

#Region Create Visio Graphics Service
Function CreateVisioServiceApp ([xml]$xmlinput)
{
	$ServiceConfig = $xmlinput.Configuration.EnterpriseServiceApps.VisioService
	If ($ServiceConfig.Provision -eq $true)
	{
		WriteLine
		$ServiceInstanceType = "Microsoft.Office.Visio.Server.Administration.VisioGraphicsServiceInstance"
		CreateBasicServiceApplication -ServiceConfig $ServiceConfig `
									  -ServiceInstanceType $ServiceInstanceType `
									  -ServiceName $ServiceConfig.Name `
									  -ServiceProxyName $ServiceConfig.ProxyName `
									  -ServiceGetCmdlet "Get-SPVisioServiceApplication" `
									  -ServiceProxyGetCmdlet "Get-SPVisioServiceApplicationProxy" `
  									  -ServiceNewCmdlet "New-SPVisioServiceApplication" `
									  -ServiceProxyNewCmdlet "New-SPVisioServiceApplicationProxy"
									  
		If (Get-Command -Name Get-SPVisioServiceApplication -ErrorAction SilentlyContinue)
		{
			Write-Host -ForegroundColor White " - Setting Visio Unattended Service Account Application ID..."
			$VisioAcct = $xmlinput.Configuration.EnterpriseServiceApps.VisioService.UnattendedIDUser
		    $VisioAcctPWD = $xmlinput.Configuration.EnterpriseServiceApps.VisioService.UnattendedIDPassword
		    If (!($VisioAcct) -or $VisioAcct -eq "" -or !($VisioAcctPWD) -or $VisioAcctPWD -eq "") 
		    {
		        Write-Host -BackgroundColor Gray -ForegroundColor DarkBlue " - Prompting for Visio Unattended Account:"
		    	$VisioCredential = $host.ui.PromptForCredential("Visio Setup", "Enter Visio Unattended Account Credentials:", "$VisioAcct", "NetBiosUserName" )
		    } 
		    Else
		    {
		        $secPassword = ConvertTo-SecureString "$VisioAcctPWD" –AsPlaintext –Force 
		        $VisioCredential = New-Object System.Management.Automation.PsCredential $VisioAcct,$secPassword
		    }
			Get-SPVisioServiceApplication | Set-SPVisioExternalData -UnattendedServiceAccountApplicationID $VisioCredential
		}
		WriteLine
	}
}
#EndRegion

#Region Create PerformancePoint Service
Function CreatePerformancePointServiceApp ([xml]$xmlinput)
{
	$ServiceConfig = $xmlinput.Configuration.EnterpriseServiceApps.PerformancePointService
	If ($ServiceConfig.Provision -eq $true)
	{
		WriteLine
		$ServiceInstanceType = "Microsoft.PerformancePoint.Scorecards.BIMonitoringServiceInstance"
		CreateBasicServiceApplication -ServiceConfig $ServiceConfig `
									  -ServiceInstanceType $ServiceInstanceType `
									  -ServiceName $ServiceConfig.Name `
									  -ServiceProxyName $ServiceConfig.ProxyName `
									  -ServiceGetCmdlet "Get-SPPerformancePointServiceApplication" `
									  -ServiceProxyGetCmdlet "Get-SPServiceApplicationProxy" `
  									  -ServiceNewCmdlet "New-SPPerformancePointServiceApplication" `
									  -ServiceProxyNewCmdlet "New-SPPerformancePointServiceApplicationProxy"
									  
	    If (Get-SPPerformancePointServiceApplication | ? {$_.DisplayName -eq $ServiceConfig.Name})
		{
			Write-Host -ForegroundColor White " - Setting PerformancePoint Data Source Unattended Service Account..."
			$PerformancePointAcct = $xmlinput.Configuration.EnterpriseServiceApps.PerformancePointService.UnattendedIDUser
		    $PerformancePointAcctPWD = $xmlinput.Configuration.EnterpriseServiceApps.PerformancePointService.UnattendedIDPassword
		    If (!($PerformancePointAcct) -or $PerformancePointAcct -eq "" -or !($PerformancePointAcctPWD) -or $PerformancePointAcctPWD -eq "") 
		    {
		        Write-Host -BackgroundColor Gray -ForegroundColor DarkBlue " - Prompting for PerformancePoint Unattended Service Account:"
		    	$PerformancePointCredential = $host.ui.PromptForCredential("PerformancePoint Setup", "Enter PerformancePoint Unattended Account Credentials:", "$PerformancePointAcct", "NetBiosUserName" )
		    } 
		    Else
		    {
		        $secPassword = ConvertTo-SecureString "$PerformancePointAcctPWD" –AsPlaintext –Force 
		        $PerformancePointCredential = New-Object System.Management.Automation.PsCredential $PerformancePointAcct,$secPassword
		    }
			Get-SPPerformancepointServiceApplication | Set-SPPerformancePointSecureDataValues -DataSourceUnattendedServiceAccount $PerformancePointCredential
			
			##Set-SPPerformancePointServiceApplication -SettingsDatabase
		}
		WriteLine
	}
}
#EndRegion

#Region Create Access Service
Function CreateAccessServiceApp ([xml]$xmlinput)
{
	$ServiceConfig = $xmlinput.Configuration.EnterpriseServiceApps.AccessService
	If ($ServiceConfig.Provision -eq $true)
	{
		WriteLine
		$ServiceInstanceType = "Microsoft.Office.Access.Server.MossHost.AccessServerWebServiceInstance"
		CreateBasicServiceApplication -ServiceConfig $ServiceConfig `
									  -ServiceInstanceType $ServiceInstanceType `
									  -ServiceName $ServiceConfig.Name `
									  -ServiceProxyName $ServiceConfig.ProxyName `
									  -ServiceGetCmdlet "Get-SPAccessServiceApplication" `
									  -ServiceProxyGetCmdlet "Get-SPServiceApplicationProxy" `
									  -ServiceNewCmdlet "New-SPAccessServiceApplication –Default" `
									  -ServiceProxyNewCmdlet "New-SPAccessServiceApplicationProxy" # Fake cmdlet (and not needed for Access Services), but the CreateBasicServiceApplication function expects something
		WriteLine
	}
}
#EndRegion

#Region Create Word Automation Service
Function CreateWordAutomationServiceApp ([xml]$xmlinput)
{
	$ServiceConfig = $xmlinput.Configuration.ServiceApps.WordAutomationService
    $DBPrefix = $xmlinput.Configuration.Farm.Database.DBPrefix
	If (($DBPrefix -ne "") -and ($DBPrefix -ne $null)) {$DBPrefix += "_"}
	If ($DBPrefix -like "*localhost*") {$DBPrefix = $DBPrefix -replace "localhost","$env:COMPUTERNAME"}
	$WordDatabase = $DBPrefix+$($ServiceConfig.Database)
	If ($ServiceConfig.Provision -eq $true)
	{
		WriteLine
		$ServiceInstanceType = "Microsoft.Office.Word.Server.Service.WordServiceInstance"
		CreateBasicServiceApplication -ServiceConfig $ServiceConfig `
									  -ServiceInstanceType $ServiceInstanceType `
									  -ServiceName $ServiceConfig.Name `
									  -ServiceProxyName $ServiceConfig.ProxyName `
									  -ServiceGetCmdlet "Get-SPServiceApplication" `
									  -ServiceProxyGetCmdlet "Get-SPServiceApplicationProxy" `
									  -ServiceNewCmdlet "New-SPWordConversionServiceApplication -DatabaseName $WordDatabase –Default" `
									  -ServiceProxyNewCmdlet "New-SPWordConversionServiceApplicationProxy" # Fake cmdlet (and not needed for Access Services), but the CreateBasicServiceApplication function expects something
		WriteLine
	}
}
#EndRegion

#Region Create Office Web Apps
Function CreateExcelOWAServiceApp ([xml]$xmlinput)
{
	$ServiceConfig = $xmlinput.Configuration.OfficeWebApps.ExcelService
	If (($ServiceConfig.Provision -eq $true) -and (Test-Path "$env:CommonProgramFiles\Microsoft Shared\Web Server Extensions\14\TEMPLATE\FEATURES\OfficeWebApps\feature.xml"))
	{
		WriteLine
		$PortalWebApp = $xmlinput.Configuration.WebApplications.WebApplication | Where {$_.Type -eq "Portal"}
		$PortalURL = $PortalWebApp.URL
		$PortalPort = $PortalWebApp.Port
		$ServiceInstanceType = "Microsoft.Office.Excel.Server.MossHost.ExcelServerWebServiceInstance"
		CreateBasicServiceApplication -ServiceConfig $ServiceConfig `
									  -ServiceInstanceType $ServiceInstanceType `
									  -ServiceName $ServiceConfig.Name `
									  -ServiceProxyName $ServiceConfig.ProxyName `
									  -ServiceGetCmdlet "Get-SPExcelServiceApplication" `
									  -ServiceProxyGetCmdlet "Get-SPServiceApplicationProxy" `
									  -ServiceNewCmdlet "New-SPExcelServiceApplication –Default" `
									  -ServiceProxyNewCmdlet "New-SPExcelServiceApplicationProxy" # Fake cmdlet (and not needed for Excel Services), but the CreateBasicServiceApplication function expects something
									  
		If (Get-SPExcelServiceApplication)
		{
			Write-Host -ForegroundColor White " - Setting Excel Services Trusted File Location..."
			Set-SPExcelFileLocation -Identity "http://" -LocationType SharePoint -IncludeChildren -Address $PortalURL`:$PortalPort -ExcelServiceApplication $($ServiceConfig.Name) -ExternalDataAllowed 2 -WorkbookSizeMax 10
		}
		WriteLine
	}
}

Function CreatePowerPointServiceApp ([xml]$xmlinput)
{
	$ServiceConfig = $xmlinput.Configuration.OfficeWebApps.PowerPointService
	If (($ServiceConfig.Provision -eq $true) -and (Test-Path "$env:CommonProgramFiles\Microsoft Shared\Web Server Extensions\14\TEMPLATE\FEATURES\OfficeWebApps\feature.xml"))
	{
		WriteLine
		$ServiceInstanceType = "Microsoft.Office.Server.PowerPoint.SharePoint.Administration.PowerPointWebServiceInstance"
		CreateBasicServiceApplication -ServiceConfig $ServiceConfig `
									  -ServiceInstanceType $ServiceInstanceType `
									  -ServiceName $ServiceConfig.Name `
									  -ServiceProxyName $ServiceConfig.ProxyName `
									  -ServiceGetCmdlet "Get-SPPowerPointServiceApplication" `
									  -ServiceProxyGetCmdlet "Get-SPPowerPointServiceApplicationProxy" `
									  -ServiceNewCmdlet "New-SPPowerPointServiceApplication" `
									  -ServiceProxyNewCmdlet "New-SPPowerPointServiceApplicationProxy"
		WriteLine
	}
}

Function CreateWordViewingServiceApp ([xml]$xmlinput)
{
	$ServiceConfig = $xmlinput.Configuration.OfficeWebApps.WordViewingService
	If (($ServiceConfig.Provision -eq $true) -and (Test-Path "$env:CommonProgramFiles\Microsoft Shared\Web Server Extensions\14\TEMPLATE\FEATURES\OfficeWebApps\feature.xml"))
	{
		WriteLine
		$ServiceInstanceType = "Microsoft.Office.Web.Environment.Sharepoint.ConversionServiceInstance"
		CreateBasicServiceApplication -ServiceConfig $ServiceConfig `
									  -ServiceInstanceType $ServiceInstanceType `
									  -ServiceName $ServiceConfig.Name `
									  -ServiceProxyName $ServiceConfig.ProxyName `
									  -ServiceGetCmdlet "Get-SPServiceApplication" `
									  -ServiceProxyGetCmdlet "Get-SPServiceApplicationProxy" `
									  -ServiceNewCmdlet "New-SPWordViewingServiceApplication" `
									  -ServiceProxyNewCmdlet "New-SPWordViewingServiceApplicationProxy"
		WriteLine
	}
}
#EndRegion

#Region Configure Outgoing Email
# This is from http://autospinstaller.codeplex.com/discussions/228507?ProjectName=autospinstaller courtesy of rybocf
Function ConfigureOutgoingEmail
{
	If ($($xmlinput.Configuration.Farm.Services.OutgoingEmail.Configure) -eq $true)
	{
		try
		{
			$SMTPServer = $xmlinput.Configuration.Farm.Services.OutgoingEmail.SMTPServer
			$EmailAddress = $xmlinput.Configuration.Farm.Services.OutgoingEmail.EmailAddress
			$ReplyToEmail = $xmlinput.Configuration.Farm.Services.OutgoingEmail.ReplyToEmail
			Write-Host -ForegroundColor White " - Configuring Outgoing Email..."
			$loadasm = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SharePoint")
			$SPGlobalAdmin =  New-Object Microsoft.SharePoint.Administration.SPGlobalAdmin
			$SPGlobalAdmin.UpdateMailSettings($SMTPServer, $EmailAddress, $ReplyToEmail, 65001)
		}
		catch
		{
			Write-Output $_
		}
	}
}
#EndRegion

#Region Miscellaneous/Utility Functions
# ===================================================================================
# Func: Load SharePoint Powershell Snapin
# Desc: Load SharePoint Powershell Snapin
# ===================================================================================
Function Load-SharePoint-Powershell
{
	If ((Get-PsSnapin |?{$_.Name -eq "Microsoft.SharePoint.PowerShell"})-eq $null)
	{
    	Write-Host -ForegroundColor White " - Loading SharePoint Powershell Snapin"
   		$PSSnapin = Add-PsSnapin Microsoft.SharePoint.PowerShell -ErrorAction SilentlyContinue | Out-Null
	}
}

# ===================================================================================
# Func: ConvertTo-PlainText
# Desc: Convert string to secure phrase
#       Used (for example) to get the Farm Account password into plain text as input to provision the User Profile Sync Service
#       From http://www.vistax64.com/powershell/159190-read-host-assecurestring-problem.html
# ===================================================================================
Function ConvertTo-PlainText( [security.securestring]$secure )
{
	$marshal = [Runtime.InteropServices.Marshal]
	$marshal::PtrToStringAuto( $marshal::SecureStringToBSTR($secure) )
}

# ===================================================================================
# Func: Pause
# Desc: Wait for user to press a key - normally used after an error has occured
# ===================================================================================
Function Pause
{
	#From http://www.microsoft.com/technet/scriptcenter/resources/pstips/jan08/pstip0118.mspx
	Write-Host "Press any key to exit..."
	$null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# ====================================================================================
# Func: Add-SQLAlias
# Desc: Creates a local SQL alias (like using cliconfg.exe) so the real SQL server/name doesn't get hard-coded in SharePoint
# From: Bill Brockbank, SharePoint MVP (billb@navantis.com)
# ====================================================================================

Function Add-SQLAlias()
{
    <#
    .Synopsis
        Add a new SQL server Alias
    .Description
        Adds a new SQL server Alias with the provided parameters.
    .Example
                Add-SQLAlias -AliasName "SharePointDB" -SQLInstance $Env:COMPUTERNAME
    .Example
                Add-SQLAlias -AliasName "SharePointDB" -SQLInstance $Env:COMPUTERNAME -Port '1433'
    .Parameter AliasName
        The new alias Name.
    .Parameter SQLInstance
                The SQL server Name os Instance Name
    .Parameter Port
        Port number of SQL server instance. This is an optional parameter.
    #>
    [CmdletBinding(DefaultParameterSetName="BuildPath+SetupInfo")]
    param
    (
        [Parameter(Mandatory=$false, ParameterSetName="BuildPath+SetupInfo")][ValidateNotNullOrEmpty()]
        [String]$AliasName = "SharePointDB",
    
        [Parameter(Mandatory=$false, ParameterSetName="BuildPath+SetupInfo")][ValidateNotNullOrEmpty()]
        [String]$SQLInstance = $Env:COMPUTERNAME,

        [Parameter(Mandatory=$false, ParameterSetName="BuildPath+SetupInfo")][ValidateNotNullOrEmpty()]
        [String]$Port = ""
    )

    $ServerAliasConnection="DBMSSOCN,$SQLInstance"
    if ($Port -ne "")
    {
         $ServerAliasConnection += ",$Port"
    }
    $NotExist=$true
    $Client=Get-Item 'HKLM:\SOFTWARE\Microsoft\MSSQLServer\Client'
    $Client.GetSubKeyNames() | ForEach-Object -Process { if ( $_ -eq 'ConnectTo') { $NotExist=$false }}
    if ($NotExist)
    {
        $Data = New-Item 'HKLM:\SOFTWARE\Microsoft\MSSQLServer\Client\ConnectTo'
    }
    #Add Alias
    $Data = New-ItemProperty HKLM:\SOFTWARE\Microsoft\MSSQLServer\Client\ConnectTo -Name $AliasName -Value $ServerAliasConnection -PropertyType "String" -Force -ErrorAction SilentlyContinue
}

# ====================================================================================
# Func: CheckSQLAccess
# Desc: Checks if the install account has the correct SQL database access and permissions
# By: 	Sameer Dhoot (http://sharemypoint.in/about/sameerdhoot/)
# From:	http://sharemypoint.in/2011/04/18/powershell-script-to-check-sql-server-connectivity-version-custering-status-user-permissions/
# Adapted for use in AutoSPInstaller by @brianlala
# ====================================================================================
Function CheckSQLAccess
{
	WriteLine
	$FarmDBServer = $xmlinput.Configuration.Farm.Database.DBServer
	$SearchDBServer = $xmlinput.Configuration.ServiceApps.EnterpriseSearchService.EnterpriseSearchServiceApplications.EnterpriseSearchServiceApplication.DatabaseServer
	If ($xmlinput.Configuration.Farm.Database.DBAlias.Create -eq $true)
	{
		$FarmDBInstance = $xmlinput.Configuration.Farm.Database.DBAlias.DBInstance
		# If no DBInstance has been specified, but Create="$True", set the Alias to the server value
		If (($FarmDBInstance -eq $null) -and ($FarmDBInstance -ne "")) {$FarmDBInstance = $FarmDBServer}
		$FarmDBPort = $xmlinput.Configuration.Farm.Database.DBAlias.DBPort
		If (($FarmDBPort -ne $null) -and ($FarmDBPort -ne "")) 
		{
			Write-Host -ForegroundColor White " - Creating SQL alias `"$FarmDBServer,$FarmDBPort`"..."
			Add-SQLAlias -AliasName $FarmDBServer -SQLInstance $FarmDBInstance -Port $FarmDBPort
		}
		Else # Create the alias without specifying the port (use default)
		{
			Write-Host -ForegroundColor White " - Creating SQL alias `"$FarmDBServer`"..."
			Add-SQLAlias -AliasName $FarmDBServer -SQLInstance $FarmDBInstance
		}
	}
	$currentUser = "$env:USERDOMAIN\$env:USERNAME"
	$serverRolesToCheck = "dbcreator","securityadmin"
	
    $DBServers = @($FarmDBServer, $SearchDBServer)
	ForEach ($sqlServer in $DBServers)
	{
		If ($sqlServer) # Only check the SQL instance if it has a value
		{
			$objSQLConnection = New-Object System.Data.SqlClient.SqlConnection
			$objSQLCommand = New-Object System.Data.SqlClient.SqlCommand
			Try
			{
				$objSQLConnection.ConnectionString = "Server=$sqlServer;Integrated Security=SSPI;"
				Write-Host -ForegroundColor White " - Testing access to SQL server/instance/alias:" $sqlServer
				Write-Host -ForegroundColor White " - Trying to connect to `"$sqlServer`"..." -NoNewline
				$objSQLConnection.Open() | Out-Null
				Write-Host -ForegroundColor Black -BackgroundColor Blue "Success"
				$strCmdSvrDetails = "SELECT SERVERPROPERTY('productversion') as Version"
				$strCmdSvrDetails += ",SERVERPROPERTY('IsClustered') as Clustering"
				$objSQLCommand.CommandText = $strCmdSvrDetails
				$objSQLCommand.Connection = $objSQLConnection
				$objSQLDataReader = $objSQLCommand.ExecuteReader()
				if($objSQLDataReader.Read())
				{
					Write-Host -ForegroundColor White (" - SQL Server version is: {0}" -f $objSQLDataReader.GetValue(0))
					if ($objSQLDataReader.GetValue(1) -eq 1)
					{
						Write-Host -ForegroundColor White " - This instance of SQL Server is clustered"
					} 
					else 
					{
						Write-Host -ForegroundColor White " - This instance of SQL Server is not clustered"
					}
				}
				$objSQLDataReader.Close()
				ForEach($serverRole in $serverRolesToCheck) 
				{
					$objSQLCommand.CommandText = "SELECT IS_SRVROLEMEMBER('$serverRole')"
					$objSQLCommand.Connection = $objSQLConnection
					Write-Host -ForegroundColor White " - Check if $currentUser has $serverRole server role..." -NoNewline
					$objSQLDataReader = $objSQLCommand.ExecuteReader()
					if ($objSQLDataReader.Read() -and $objSQLDataReader.GetValue(0) -eq 1)
					{
						Write-Host -BackgroundColor Blue -ForegroundColor Black "Pass"
					}
					elseif($objSQLDataReader.GetValue(0) -eq 0) 
					{
						Write-Host -ForegroundColor Red "Fail"
					}
					else 
					{
						Write-Host -ForegroundColor Red "Invalid Role"
					}
					$objSQLDataReader.Close()
				}
				$objSQLConnection.Close()
			}
			Catch 
			{
				Write-Host -ForegroundColor Red "Fail"
				$errText =  $Error[0].ToString()
				if ($errText.Contains("network-related"))
				{
					Write-Host -ForegroundColor Red " - Connection Error. Check server name, port, firewall."
				}
				elseif ($errText.Contains("Login failed"))
				{
					Write-Host -ForegroundColor Red " - Not able to login. SQL Server login not created."
				}
				Write-Host -ForegroundColor Red $errText
				Pause
				Break
			}
		}
	}
	WriteLine
}
# ====================================================================================
# Func: WriteLine
# Desc: Writes a nice line of dashes across the screen
# ====================================================================================
Function WriteLine
{
	Write-Host -ForegroundColor White "--------------------------------------------------------------"
}

# ====================================================================================
# Func: Run-HealthAnalyzerJobs
# Desc: Runs all Health Analyzer Timer Jobs Immediately
# From: http://www.sharepointconfig.com/2011/01/instant-sharepoint-health-analysis/
# ====================================================================================
Function Run-HealthAnalyzerJobs
{
	$HealthJobs = Get-SPTimerJob | Where {$_.DisplayName -match "Health Analysis Job"}
	Write-Host -ForegroundColor White " - Running all Health Analyzer jobs..."
	ForEach ($Job in $HealthJobs)
	{
		$Job.RunNow()
	}
}

# ====================================================================================
# Func: Add-SMTP
# Desc: Adds the SMTP Server Windows feature
# ====================================================================================
Function Add-SMTP
{
	Write-Host -ForegroundColor White " - Installing SMTP Server feature..."
	Try
	{
		Import-Module ServerManager
		Add-WindowsFeature -Name SMTP-Server | Out-Null
		If (!($?)) {Throw " - Failed to install SMTP Server!"}
	}
	Catch {}
	Write-Host -ForegroundColor White " - Done."
}

# ====================================================================================
# Func: FixTaxonomyPickerBug
# Desc: Implements the fix suggested in http://support.microsoft.com/kb/2481844
# ====================================================================================
Function FixTaxonomyPickerBug
{
	$TaxonomyPicker = "$env:CommonProgramFiles\Microsoft Shared\Web Server Extensions\14\TEMPLATE\CONTROLTEMPLATES\TaxonomyPicker.ascx"
	$TaxonomyPickerContent = (Get-Content $TaxonomyPicker)
	If ($TaxonomyPickerContent | Select-String -Pattern '&#44;' -SimpleMatch)
	{
		WriteLine
		Write-Host -ForegroundColor White " - Fixing TaxonomyPicker.ascx..."
		Write-Host -ForegroundColor White " - Making a backup copy of TaxonomyPicker.ascx..."
		Copy-Item $TaxonomyPicker $TaxonomyPicker".bad"
		$NewTaxonomyPickerControlContent = $TaxonomyPickerContent -replace '&#44;', ","
		Write-Host -ForegroundColor White " - Writing out new TaxonomyPicker.ascx..."
		Set-Content -Path $TaxonomyPicker -Value $NewTaxonomyPickerControlContent
		Write-Host -ForegroundColor White " - Done."
		WriteLine
	}
}
#EndRegion