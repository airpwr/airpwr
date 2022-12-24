$ProgressPreference = 'SilentlyContinue'

if ($env:PwrLoadedPackages -or $env:PwrShellPackages) {
	Write-Error "already running pwr with packages $(if ($env:PwrLoadedPackages) { $env:PwrLoadedPackages } else { $env:PwrShellPackages })"
}

$script:PwrVersion = $env:PwrVersion
if (-not $script:PwrVersion) {
	$C = [System.Net.WebClient]::new()
	try {
		$Tags = $C.DownloadString('https://api.github.com/repos/airpwr/airpwr/tags') | ConvertFrom-Json
	} catch {
		Write-Error 'could not get pwr tags'
		throw $_
	} finally {
		$C.Dispose()
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
$C = [System.Net.WebClient]::new()
try {
	$C.DownloadFile("https://raw.githubusercontent.com/airpwr/airpwr/v$script:PwrVersion/src/pwr.ps1", $PwrScriptPath)
} catch {
	Write-Error 'could not to download pwr script'
	throw $_
} finally {
	$C.Dispose()
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
