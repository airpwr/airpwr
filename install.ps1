# Copies the built Airpower module to the $env:PSModulePath user directory.
# Equivalent to `Install-Module Airpower -Scope CurrentUser`.
# Useful if powershellgallery.com is not available.

. $PSScriptRoot\build.ps1
$dir = "${HOME}\Documents\WindowsPowerShell\Modules\Airpower\$(GetModuleVersion)"
mkdir -p $dir -ErrorAction SilentlyContinue | Out-Null
Get-ChildItem $buildDir | ForEach-Object {
	Copy-Item $_.FullName $dir
	Unblock-File "$dir\$_"
	Write-Output "$dir\$_"
}
