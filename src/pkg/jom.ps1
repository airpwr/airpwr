. $PSScriptRoot\..\github.ps1

function AirpowerPackageJom {
	param (
		[string]$TagName,
		[string]$Digest
	)
	return AirpowerGitHubPackage -Owner 'qt-labs' -Repo 'jom' -Digest $Digest -TagName $TagName -TagPattern '^v([0-9]+)\.([0-9]+)\.([0-9]+)$' -UrlFormat 'http://qt.mirror.constant.com/official_releases/jom/jom_{0}.zip' -IncludeFiles 'jom.exe'
}
