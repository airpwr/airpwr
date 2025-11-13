function BuildPsm1 {
	$file = "$PSScriptRoot\src\pwr.ps1"
	$script:seen = @($file)
	$parse = {
		param (
			[string]$path
		)
		$content = ''
		foreach ($line in (Get-Content $path)) {
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
	"0.7.1"
}

$buildDir = "$PSScriptRoot\build\Airpower"
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
	FormatsToProcess = @('Airpower.Format.ps1xml')
	CmdletsToExport = @()
	VariablesToExport = ''
	AliasesToExport = @('airpower', 'air', 'pwr')
	PrivateData = @{
		PSData = @{
			Tags = @('windows', 'docker', 'package-manager', 'package', 'development', 'powershell', 'container', 'configuration', 'airpower', 'airpwr')
			LicenseUri = 'https://github.com/airpwr/airpwr/blob/main/LICENSE.md'
			ProjectUri = 'https://github.com/airpwr/airpwr'
		}
	}
}
"@
Out-File "$buildDir\Airpower.Format.ps1xml" -Encoding ascii -Force -InputObject @"
<?xml version="1.0" encoding="utf-8"?>
<Configuration>
	<ViewDefinitions>
		<View>
			<Name>Airpower.LocalPackage</Name>
				<ViewSelectedBy>
					<TypeName>LocalPackage</TypeName>
				</ViewSelectedBy>
				<TableControl>
					<TableHeaders />
					<TableRowEntries>
						<TableRowEntry>
							<TableColumnItems>
								<TableColumnItem>
									<PropertyName>Package</PropertyName>
								</TableColumnItem>
								<TableColumnItem>
									<PropertyName>Tag</PropertyName>
								</TableColumnItem>
								<TableColumnItem>
									<PropertyName>Version</PropertyName>
								</TableColumnItem>
								<TableColumnItem>
									<PropertyName>Digest</PropertyName>
								</TableColumnItem>
								<TableColumnItem>
									<PropertyName>Size</PropertyName>
								</TableColumnItem>
							</TableColumnItems>
						</TableRowEntry>
					</TableRowEntries>
				</TableControl>
			</View>
	</ViewDefinitions>
</Configuration>
"@
