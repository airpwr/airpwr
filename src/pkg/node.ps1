. $PSScriptRoot\..\github.ps1

function AirpowerPackageNode {
	param (
		[string]$TagName,
		[string]$Digest
	)
	return AirpowerGitHubPackage -Owner 'nodejs' -Repo 'node' -Digest $Digest -TagName $TagName -TagPattern '^v([0-9]+)\.([0-9]+)\.([0-9]+)$' -UrlFormat 'https://nodejs.org/dist/v{0}/node-v{0}-win-x64.zip' -IncludeFiles 'node.exe'
}
