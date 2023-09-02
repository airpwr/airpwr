. $PSScriptRoot\..\github.ps1

function AirpowerPackagePowershell {
	param (
		[string]$TagName,
		[string]$Digest
	)
	return AirpowerGitHubPackage -Owner 'PowerShell' -Repo 'PowerShell' -Digest $Digest -TagName $TagName -TagPattern '^v([0-9]+)\.([0-9]+)\.([0-9]+)$' -UrlFormat 'https://github.com/PowerShell/PowerShell/releases/download/v{0}/PowerShell-{0}-win-x64.zip' -IncludeFiles 'pwsh.exe'
}
