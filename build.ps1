function BuildPsm1 {
	$file = '.\src\pwr.ps1'
	$script:seen = @($file)
	$parse = {
		param (
			[string]$path
		)
		$content = ''
		foreach ($line in [IO.File]::ReadAllLines($path)) {
			if ($line -match '^\. \$PSScriptRoot\\(.+)\.ps1$') {
				$file = ".\src\$($Matches[1]).ps1"
				if ($file -notin $seen) {
					$script:seen += $file
					$content += & $parse $file
				}
			} else {
				$content += $line + "`r`n"
			}
		}
		return $content
	}
	return & $parse $file
}

function GetModuleVersion {
	if ((git describe --tag) -match '^v([0-9]+\.[0-9]+\.[0-9]+).*$') {
		$Matches[1]
	} else {
		throw "failed to get tag"
	}
}

$buildDir = '.\build\Airpower'
if (-not (Test-Path $buildDir -PathType Container)) {
	New-Item -Path $buildDir -ItemType Directory | Out-Null
}

Out-File "$buildDir\Airpower.psm1" -Encoding ascii -Force -InputObject (BuildPsm1)
Out-File "$buildDir\Airpower.psd1" -Encoding ascii -Force -InputObject @"
@{
	RootModule = 'Airpower.psm1'
	ModuleVersion = '$(GetModuleVersion)'
	CompatiblePSEditions = @('Windows')
	GUID = '12d99217-b208-4995-8cdf-26e4cf695588'
	PowerShellVersion = '5.1'
	Author = 'Airpower Team'
	CompanyName = 'Airpower Team'
	Copyright = 'U.S. Federal Government (in countries where recognized)'
	Description = 'A package manager and environment to provide consistent tooling for software teams.'
	FunctionsToExport = @('Invoke-Airpower')
	CmdletsToExport = @()
	VariablesToExport = ''
	AliasesToExport = @('pwr')
	PrivateData = @{
		PSData = @{
			Tags = @('windows', 'docker', 'package-manager', 'package', 'development', 'powershell', 'container', 'configuration', 'airpower', 'airpwr', 'pwr')
			LicenseUri = 'https://github.com/airpwr/airpwr/blob/main/LICENSE.md'
			ProjectUri = 'https://github.com/airpwr/airpwr'
		}
	}
}
"@
