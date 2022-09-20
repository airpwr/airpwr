$ProgressPreference = 'SilentlyContinue'

# Required for curl.exe
if ([Environment]::OSVersion.Version.Build -lt 17063) {
	Write-Error "windows build version $([Environment]::OSVersion.Version.Build) does not meet minimum required build version 17063; update windows to use pwr"
} elseif ($env:PwrLoadedPackages -or $env:PwrShellPackages) {
	Write-Error "already running pwr with packages $(if ($env:PwrLoadedPackages) { $env:PwrLoadedPackages } else { $env:PwrShellPackages })"
}

$script:PwrVersion = $env:PwrVersion
if (-not $script:PwrVersion) {
	$Tags = & "$env:SYSTEMROOT\System32\curl.exe" -s --url 'https://api.github.com/repos/airpwr/airpwr/tags' | ConvertFrom-Json
	if ($global:LASTEXITCODE) {
		Write-Error 'could not get pwr tags'
		throw
	}
	$script:PwrVersion = $Tags[0].Name.Substring(1)
}

$PwrPath = if ($env:PwrHome) { $env:PwrHome } else { "$env:AppData\pwr" }
$PwrCmd = "$PwrPath\cmd"
$PwrScriptPath = "$PwrCmd\pwr.ps1"
mkdir $PwrCmd -Force | Out-Null
if ($script:PwrVersion -notmatch '^[0-9]+\.[0-9]+(\.[0-9]+)?$') {
	Write-Error 'version does not match the expected pattern'
}
& "$env:SYSTEMROOT\System32\curl.exe" -s --url "https://raw.githubusercontent.com/airpwr/airpwr/v$script:PwrVersion/src/pwr.ps1" --output $PwrScriptPath
if ($global:LASTEXITCODE) {
	Write-Error 'could not to download pwr script'
	throw
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
	}
} catch {
	Write-Error $_
	Write-Error "could not run pwr script; make sure it was installed correctly at $PwrScriptPath"
}

Write-Host "pwr: " -ForegroundColor Blue -NoNewline
Write-Host "version $env:PwrVersion sha256:$((Get-FileHash -Path $PwrScriptPath -Algorithm SHA256).Hash.ToLower())"
