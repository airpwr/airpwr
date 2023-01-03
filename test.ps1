param (
	[string[]]$Paths
)
if (-not (Test-Path .\.modules)) {
	New-Item -Path .\.modules -ItemType Directory
}

foreach ($name in 'Pester', 'PSScriptAnalyzer') {
	if (-not (Test-Path ".\.modules\$name")) {
		Save-Module -Name $name -Path .\.modules
	}
	Import-Module (Get-ChildItem -Path ".\.modules\$name" -Recurse -Include "$name.psd1").Fullname
}

$analysis = Invoke-ScriptAnalyzer -Severity Warning -Path 'src' -ExcludeRule 'PSAvoidUsingWriteHost', 'PSUseProcessBlockForPipelineCommand', 'PSUseBOMForUnicodeEncodedFile'

if ($analysis.Count -gt 0) {
	$analysis
	throw "failed with $($analysis.Count) findings"
}

$global:PesterPreference = (New-PesterConfiguration -Hashtable @{
	Run = @{
		Path = if ($Paths) { $Paths } else { @('.\src') }
	}
	CodeCoverage = @{
		Enabled = $true
	}
})

$global:PesterPreference.CodeCoverage.CoveragePercentTarget = 100

Invoke-Pester -Configuration $PesterPreference
