param (
	[string[]]$Paths
)

$Paths = if ($Paths) { $Paths } else { @('.\src') }

$modules = 'ps_modules'

if (-not (Test-Path $modules)) {
	New-Item -Path $modules -ItemType Directory | Out-Null
}

foreach ($name in 'Pester', 'PSScriptAnalyzer') {
	if (-not (Test-Path "$modules\$name")) {
		Save-Module -Name $name -Path $modules
	}
	Remove-Module -Name $name -ErrorAction SilentlyContinue
	Import-Module (Get-ChildItem -Path "$modules\$name" -Recurse -Include "$name.psd1").Fullname
}

foreach ($path in $Paths) {
	$analysis = Invoke-ScriptAnalyzer -Severity Warning -Path $path -ExcludeRule 'PSAvoidUsingWriteHost', 'PSUseProcessBlockForPipelineCommand', 'PSUseBOMForUnicodeEncodedFile'
	if ($analysis.Count -gt 0) {
		$analysis
		throw "failed with $($analysis.Count) findings"
	}
}

$global:PesterPreference = (New-PesterConfiguration -Hashtable @{
	Run = @{
		Path = $Paths
	}
	CodeCoverage = @{
		Enabled = $true
	}
})

$global:PesterPreference.CodeCoverage.CoveragePercentTarget = 100

Invoke-Pester -Configuration $PesterPreference
