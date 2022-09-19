param (
	[Parameter(Position = 0)]
	[ValidatePattern('^[0-9]+\.[0-9]+(\.[0-9]+)?$')]
	[string]$Version
)

$ProgressPreference = 'SilentlyContinue'

# Required for curl.exe
if ([Environment]::OSVersion.Version.Build -lt 17063) {
	Write-Error "windows build version $([Environment]::OSVersion.Version.Build) does not meet minimum required build version 17063; update windows to use pwr"
	exit 1
}

if (-not $Version) {
	$Tags = & "$env:SYSTEMROOT\System32\curl.exe" -s --url 'https://api.github.com/repos/airpwr/airpwr/tags' | ConvertFrom-Json
	if ($global:LASTEXITCODE) {
		Write-Error 'could not get pwr tags'
		exit 1
	}
	$Version = $Tags[0].Name.Substring(1)
}

$PwrPath = if ($env:PwrHome) { $env:PwrHome } else { "$env:AppData\pwr" }
$PwrCmd = "$PwrPath\cmd"
$PwrScriptPath = "$PwrCmd\pwr.ps1"
mkdir $PwrCmd -Force | Out-Null
& "$env:SYSTEMROOT\System32\curl.exe" -s --url "https://raw.githubusercontent.com/airpwr/airpwr/v$Version/src/pwr.ps1" --output $PwrScriptPath
if ($global:LASTEXITCODE) {
	Write-Error 'could not to download pwr script'
	exit 1
}
$UserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not $UserPath.Contains($PwrCmd)) {
	[Environment]::SetEnvironmentVariable('Path', "$UserPath;$PwrCmd", 'User')
}
if (-not "$env:Path".Contains($PwrCmd)) {
	$env:Path = "$env:Path;$PwrCmd"
}
try {
	& $PwrScriptPath | Out-Null
	if ($global:LASTEXITCODE) {
		Write-Error "pwr script finished with non-zero exit value $global:LASTEXITCODE"
		exit 1
	}
} catch {
	Write-Error $_
	Write-Error "could not run pwr script; make sure it was installed correctly at $PwrScriptPath"
	exit 1
}

Write-Host "pwr: " -ForegroundColor Blue -NoNewline
Write-Host "version $env:PwrVersion sha256:$((Get-FileHash -Path $PwrScriptPath -Algorithm SHA256).Hash.ToLower())"
