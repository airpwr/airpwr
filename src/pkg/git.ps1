. $PSScriptRoot\..\github.ps1

function AirpowerPackageGit {
	param (
		[string]$TagName,
		[string]$Digest
	)
	return AirpowerGitHubPackage -Owner 'git-for-windows' -Repo 'git' -Digest $Digest -TagName $TagName -TagPattern '^v([0-9]+)\.([0-9]+)\.([0-9]+)\.windows\.([0-9]+)$' -UrlFormat 'https://github.com/git-for-windows/git/releases/download/v{1}.{2}.{3}.windows.{4}/PortableGit-{0}-64-bit.7z.exe' -FileExtension '7z' -IncludeFiles 'gitk.exe', 'sed.exe', 'curl.exe'
}
