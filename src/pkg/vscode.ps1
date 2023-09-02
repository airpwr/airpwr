. $PSScriptRoot\..\github.ps1

function AirpowerPackageVscode {
	param (
		[string]$TagName,
		[string]$Digest
	)
	return AirpowerGitHubPackage -Owner 'microsoft' -Repo 'vscode' -Digest $Digest -TagName $TagName -TagPattern '^([0-9]+)\.([0-9]+)\.([0-9]+)$' -UrlFormat 'https://code.visualstudio.com/sha/download?build=stable&os=win32-x64-archive' -IncludeFiles 'code.cmd'
}
