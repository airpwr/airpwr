. $PSScriptRoot\..\github.ps1

function AirpowerPackageLlvm {
	param (
		[string]$TagName,
		[string]$Digest
	)
	return AirpowerGitHubPackage -Owner 'llvm' -Repo 'llvm-project' -Digest $Digest -TagName $TagName -TagPattern '^llvmorg-([0-9]+)\.([0-9]+)\.([0-9]+)$' -UrlFormat 'https://github.com/llvm/llvm-project/releases/download/llvmorg-{0}/LLVM-{0}-win64.exe' -FileExtension '7z' -IncludeFiles 'clang.exe'
}
