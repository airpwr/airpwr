. $PSScriptRoot\..\github.ps1

function AirpowerPackageNinja {
	param (
		[string]$TagName,
		[string]$Digest
	)
	return AirpowerGitHubPackage -Owner 'ninja-build' -Repo 'ninja' -Digest $Digest -TagName $TagName -TagPattern '^v([0-9]+)\.([0-9]+)\.([0-9]+)$' -UrlFormat 'https://github.com/ninja-build/ninja/releases/download/v{0}/ninja-win.zip' -IncludeFiles 'ninja.exe'
}
