$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$PwrPath = if ($env:PwrHome) { $env:PwrHome } else { "$env:appdata\pwr" }
$PwrCmd = "$PwrPath\cmd"
mkdir $PwrCmd -Force | Out-Null
Invoke-WebRequest -UseBasicParsing 'https://raw.githubusercontent.com/airpwr/airpwr/main/src/pwr.ps1' -OutFile "$PwrCmd\pwr.ps1"
$UserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not $UserPath.Contains($PwrCmd)) {
	[Environment]::SetEnvironmentVariable('Path', "$UserPath;$PwrCmd", 'User')
}
if (-not ${env:Path}.Contains($PwrCmd)) {
	$env:Path = "$env:Path;$PwrCmd"
}
& "$PwrCmd\pwr.ps1" version