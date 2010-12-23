# ===================================================================================
# CUSTOM FUNCTIONS - Put your new or overriding functions here
# ===================================================================================

#Region Custom Functions
# ===================================================================================
# FUNC: Get Version
# DESC: Gets the version of the installation
# ===================================================================================
function GetVersion()
{
    ## Detect installer/product version
    #$0 = $myInvocation.MyCommand.Definition
    #$dp0 = [System.IO.Path]::GetDirectoryName($0)
    #$bits = Get-Item $dp0 | Split-Path -Parent
    [string]$bits = Get-Location
    write-host (Get-Command "$bits\setup.exe" -ErrorAction SilentlyContinue).FileVersionInfo.ProductVersion
}
#EndRegion