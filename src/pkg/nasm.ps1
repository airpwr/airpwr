. $PSScriptRoot\..\github.ps1

function AirpowerPackageNasm {
	param (
		[string]$TagName,
		[string]$Digest
	)
	return AirpowerGitHubPackage -Owner 'netwide-assembler' -Repo 'nasm' -Digest $Digest -TagName $TagName -TagPattern '^.*([0-9]+)\.([0-9]+)\.([0-9]+)$' -UrlFormat 'https://www.nasm.us/pub/nasm/releasebuilds/{0}/win64/nasm-{0}-win64.zip' -IncludeFiles 'nasm.exe'
}
