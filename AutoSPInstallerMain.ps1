param 
(
    [string]$InputFile = $(throw '- Need parameter input file (e.g. "c:\SP2010\AutoSPInstaller\AutoSPInstallerInput.xml")')
)

##$xmlinput = [xml] (get-content $InputFile)
# Globally update all instances of "localhost" in the input file to actual local server name
[xml]$xmlinput = (Get-Content $InputFile) -replace ("localhost", $env:COMPUTERNAME)

# ===================================================================================
#
# AutoSPInstaller - See # MAIN for what to run
#
# ===================================================================================

#Region Setup Paths

$Host.UI.RawUI.WindowTitle = " -- AutoSPInstaller --"
$0 = $myInvocation.MyCommand.Definition
$dp0 = [System.IO.Path]::GetDirectoryName($0)
$bits = Get-Item $dp0 | Split-Path -Parent
# Check if SharePoint binaries are in the \SharePoint subfolder as per new folder structure
If (Test-Path -Path "$bits\SharePoint\setup.exe")
{
	$SPbits = $bits+"\SharePoint"
}
Else # Use old path convention
{
	$SPbits = $bits
}

$env:14="$env:CommonProgramFiles\Microsoft Shared\Web Server Extensions\14"
[Environment]::SetEnvironmentVariable("14", $env:14, "Machine")

$PSConfig = "$env:CommonProgramFiles\Microsoft Shared\Web Server Extensions\14\BIN\psconfig.exe"
$PSConfigUI = "$env:CommonProgramFiles\Microsoft Shared\Web Server Extensions\14\BIN\psconfigui.exe"

$script:DBPrefix = $xmlinput.Configuration.Farm.Database.DBPrefix
If (($DBPrefix -ne "") -and ($DBPrefix -ne $null)) {$script:DBPrefix += "_"}
If ($DBPrefix -like "*localhost*") {$script:DBPrefix = $DBPrefix -replace "localhost","$env:COMPUTERNAME"}

#EndRegion

#Region External Functions
. "$dp0\AutoSPInstallerFunctions.ps1"
. "$dp0\AutoSPInstallerFunctionsCustom.ps1"
#EndRegion

#Region Prepare For Install
Function PrepForInstall
{
	ValidateCredentials $xmlinput
	ValidatePassphrase $xmlinput
    CheckConfig
    CheckSQLAccess
}
#EndRegion

#Region Install SharePoint binaries
Function Run-Install
{
	Write-Host -ForegroundColor White " - Install based on:" `n" - "$InputFile `n" - Environment: "$($xmlinput.Configuration.getAttribute("Environment")) `n" - Version: "$($xmlinput.Configuration.getAttribute("Version")) 
	DisableLoopbackCheck $xmlinput
	RemoveIEEnhancedSecurity $xmlinput
	DisableServices $xmlinput
	DisableCRLCheck $xmlinput
	InstallPrerequisites $xmlinput
	InstallSharePoint $xmlinput
	InstallOfficeWebApps ($xmlinput)
	InstallLanguagePacks $xmlinput
	FixTaxonomyPickerBug
}
#EndRegion

#Region Setup Farm
Function Setup-Farm
{
    [System.Management.Automation.PsCredential]$farmCredential  = GetFarmCredentials ($xmlinput) 
    [security.securestring]$SecPhrase = GetSecureFarmPassphrase ($xmlinput)
    ConfigureFarmAdmin ($xmlinput)
    Load-SharePoint-Powershell
    CreateOrJoinFarm ($xmlinput) ([security.securestring]$SecPhrase) ([System.Management.Automation.PsCredential]$farmCredential)
    CheckFarmTopology ($xmlinput)
    ConfigureFarm ($xmlinput)
    ConfigureOfficeWebApps ($xmlinput)
    ConfigureLanguagePacks ($xmlinput)
    AddManagedAccounts ($xmlinput)   
    CreateWebApplications ($xmlinput)
}
#EndRegion

#Region Setup Services
Function Setup-Services
{
    StartSandboxedCodeService ($xmlinput)
    CreateMetadataServiceApp ($xmlinput)
	StartSearchQueryAndSiteSettingsService
	StartClaimsToWindowsTokenService ($xmlinput)
	CreateUserProfileServiceApplication ($xmlinput)
	CreateStateServiceApp ($xmlinput)
	CreateSPUsageApp ($xmlinput)
	CreateWebAnalyticsApp ($xmlinput)
	CreateSecureStoreServiceApp ($xmlinput)
	ConfigureFoundationSearch ($xmlinput)
	ConfigureTracing ($xmlinput)
	CreateEnterpriseSearchServiceApp ($xmlinput)
	CreateBusinessDataConnectivityServiceApp ($xmlinput)
	CreateExcelServiceApp ($xmlinput)
	CreateAccessServiceApp ($xmlinput)
	CreateVisioServiceApp ($xmlinput)
	CreatePerformancePointServiceApp ($xmlinput)
	CreateWordAutomationServiceApp ($xmlinput)
	CreateExcelOWAServiceApp ($xmlinput)
	CreatePowerPointServiceApp ($xmlinput)
	CreateWordViewingServiceApp ($xmlinput)
	ConfigureOutgoingEmail ($xmlinput)
	Configure-PDFSearchAndIcon ($xmlinput)
	InstallForeFront ($xmlinput)
}
#EndRegion

#Region Finalize Install (perform any cleanup operations)
# Run last
Function Finalize-Install 
{
	# Remove Farm Account from local Administrators group to avoid big scary warnings in Central Admin
	# But only if the script actually put it there, and we want to leave it there 
	# (e.g. to work around the issue with native SharePoint backups deprovisioning UPS per http://www.toddklindt.com/blog/Lists/Posts/Post.aspx?ID=275)
	$FarmAcct = $xmlinput.Configuration.Farm.Account.Username
	If (!($RunningAsFarmAcct) -and ($xmlinput.Configuration.Farm.Account.getAttribute("AddToLocalAdminsDuringSetup") -eq $true) -and ($xmlinput.Configuration.Farm.Account.LeaveInLocalAdmins -eq $false))
	{
		Write-Host -ForegroundColor White " - Removing $FarmAcct from local Administrators..."
		$FarmAcctDomain,$FarmAcctUser = $FarmAcct -Split "\\"
		try
		{
			([ADSI]"WinNT://$env:COMPUTERNAME/Administrators,group").Remove("WinNT://$FarmAcctDomain/$FarmAcctUser")
			If (-not $?) {throw}
		}
		catch {Write-Host -ForegroundColor White " - $FarmAcct already removed from Administrators."}
		# Restart SPTimerV4 so it can now run under non-local Admin privileges and avoid Health Analyzer warning
		Write-Host -ForegroundColor White " - Restarting SharePoint Timer Service..."
		Restart-Service SPTimerV4
	}
	Else
	{
		Write-Host -ForegroundColor White " - Leaving $FarmAcct in the local Administrators group."	
	}

	Run-HealthAnalyzerJobs

	# Launch Central Admin
	If (ShouldIProvision($xmlinput.Configuration.Farm.CentralAdmin) -eq $true)
	{
		$CentralAdminPort = $xmlinput.Configuration.Farm.CentralAdmin.CentralAdminPort
		Write-Host -ForegroundColor White " - Launching Central Admin..."
		Start-Process $PSConfigUI -ArgumentList "-cmd showcentraladmin"
		##Start-Process "http://$($env:COMPUTERNAME):$CentralAdminPort/_admin/adminconfigintro.aspx?scenarioid=adminconfig&welcomestringid=farmconfigurationwizard_welcome" -WindowStyle Normal
	}
	
	Write-Host -ForegroundColor White " - Completed!`a"
	$Host.UI.RawUI.WindowTitle = " -- Completed -- "
	$EndDate = Get-Date
	Write-Host -ForegroundColor White "-----------------------------------"
	Write-Host -ForegroundColor White "| Automated SP2010 install script |"
	Write-Host -ForegroundColor White "| Started on: $StartDate |"
	Write-Host -ForegroundColor White "| Completed:  $EndDate |"
	Write-Host -ForegroundColor White "-----------------------------------"

	# Launch any site collections we created
	ForEach ($webApp in $xmlinput.Configuration.WebApplications.WebApplication)
	{
		ForEach ($SiteCollection in $webApp.SiteCollections.SiteCollection)
		{
			Start-Sleep 30 # Wait for the previous site to load before trying to load this site
			$SiteURL = $SiteCollection.siteURL
			Write-Host -ForegroundColor White " - Launching $SiteURL..."
			Start-Process "$SiteURL" -WindowStyle Minimized
		}
	}

}
#EndRegion

#Region MAIN - Check for input file and start the install

StartTracing
Try 
{
	PrepForInstall
	Run-Install
	Setup-Farm
	Setup-Services
	Finalize-Install 
}
Catch 
{
	WriteLine
	Write-Host -ForegroundColor Yellow "Script aborted!"	
	If ($_.FullyQualifiedErrorId -ne $null -and $_.FullyQualifiedErrorId.StartsWith(" - ")) 
	{
		#Error messages starting " - " are thrown directly from this script
		Write-Host -ForegroundColor Red $_.FullyQualifiedErrorId
	}
	Else
	{
		#Other error messages are exceptions. Can't find a way to make this Red
		$_ | Format-List -Force
	}
	$EndDate = Get-Date
	Write-Host -ForegroundColor White "-----------------------------------"
	Write-Host -ForegroundColor White "| Automated SP2010 install script |"
	Write-Host -ForegroundColor White "| Started on: $StartDate |"
	Write-Host -ForegroundColor White "| Aborted:    $EndDate |"
	Write-Host -ForegroundColor White "-----------------------------------"
}
Finally 
{
	Stop-Transcript
	Pause
	Invoke-Item $LogFile
}


# ===================================================================================
# LOAD ASSEMBLIES
# ===================================================================================
#[void][System.Reflection.Assembly]::Load("Microsoft.SharePoint, Version=14.0.0.0, Culture=neutral, PublicKeyToken=71e9bce111e9429c") 
