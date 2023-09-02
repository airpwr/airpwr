. $PSScriptRoot\..\github.ps1

function AirpowerPackageZig {
	param (
		[string]$TagName,
		[string]$Digest
	)
	return AirpowerGitHubPackage -Owner 'ziglang' -Repo 'zig' -Digest $Digest -TagName $TagName -TagPattern '^([0-9]+)\.([0-9]+)\.?([0-9]+)?$' -UrlFormat "https://ziglang.org/download/{0}/zig-windows-x86_64-{0}.zip" -IncludeFiles 'zig.exe'
}
