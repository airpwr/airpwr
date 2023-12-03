if (-not (Test-Path "$PSScriptRoot\pwr" -Type Container)) {
	New-Item "$PSScriptRoot\pwr" -Type Container | Out-Null
}
$env:AirpowerPath = "$PSScriptRoot\pwr"

& $PSScriptRoot\build.ps1
Remove-Module Airpower -ErrorAction Ignore
Import-Module $PSScriptRoot\build\Airpower\Airpower.psd1
