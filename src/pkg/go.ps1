. $PSScriptRoot\..\github.ps1

function AirpowerPackageGo {
	param (
		[string]$TagName,
		[string]$Digest
	)
	return AirpowerGitHubPackage -Owner 'golang' -Repo 'go' -Digest $Digest -TagName $TagName -TagPattern '^go([0-9]+)\.([0-9]+)\.?([0-9]+)?$' -UrlFormat 'https://go.dev/dl/go{0}.windows-amd64.zip' -IncludeFiles 'go.exe'
}
