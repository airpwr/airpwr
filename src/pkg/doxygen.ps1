. $PSScriptRoot\..\github.ps1

function AirpowerPackageDoxygen {
	param (
		[string]$TagName,
		[string]$Digest
	)
	return AirpowerGitHubPackage -Owner 'doxygen' -Repo 'doxygen' -Digest $Digest -TagName $TagName -TagPattern '^Release_([0-9]+)_([0-9]+)_([0-9]+)$' -UrlFormat 'https://www.doxygen.nl/files/doxygen-{0}.windows.x64.bin.zip' -IncludeFiles 'doxygen.exe'
}
