param (
	[string]$TestName
)

$env:PwrHome = $null
if (-not (Test-Path "$env:AppData\pwr" -PathType Container)) {
	mkdir "$env:AppData\pwr" -Force | Out-Null
}
$env:Path = "$PSScriptRoot\..\src;$env:Path"

###### Assertions ######
function Invoke-PwrAssertTrue($block) {
	$result = Invoke-Command -ScriptBlock $block
	if ((-not $?) -or (-not $result)) {
		Write-Error "Assertion Failed: $block"
		throw
	}
}

function Invoke-PwrAssertThrows($block) {
	$LASTEXITCODE = $null
	try {
		Invoke-Command -ScriptBlock $block *> $null
	} catch {
		$LASTEXITCODE = 1
	}
	if ($LASTEXITCODE -eq 0) {
		Write-Error "Assertion Failed to Throw: $block"
		throw
	}
}

function Invoke-PwrAssertNoThrows($block) {
	try {
		Invoke-Command -ScriptBlock $block | Out-Null
	} catch {
		Write-Error "Assertion Threw: $_"
	}
}

###### Tests ######

function Test-Pwr-BuildVersions {
	. pwr v -Quiet
	Invoke-PwrAssertTrue {
		$s = '1.2.3+4'
		$v = [SemanticVersion]::new($s)
		$s -eq $v.ToString()
	}
	Invoke-PwrAssertTrue {
		$s = '1.2.3'
		$v = [SemanticVersion]::new($s)
		$s -eq $v.ToString()
	}
	Invoke-PwrAssertTrue {
		[SemanticVersion]::new('1.1.1').CompareTo([SemanticVersion]::new('1.1.1+0')) -eq 0
	}
	Invoke-PwrAssertTrue {
		[SemanticVersion]::new('1.1.1').CompareTo([SemanticVersion]::new('1.1.1+1')) -lt 0
	}
	Invoke-PwrAssertTrue {
		[SemanticVersion]::new('1.1.1').CompareTo([SemanticVersion]::new('1.1.0+1')) -gt 0
	}
	Invoke-PwrAssertTrue {
		[SemanticVersion]::new('1.1.1+1').CompareTo([SemanticVersion]::new('1.1.1+1')) -eq 0
	}
	Invoke-PwrAssertTrue {
		[SemanticVersion]::new('1.1.1+1').CompareTo([SemanticVersion]::new('1.1.1+2')) -lt 0
	}
	Invoke-PwrAssertTrue {
		[SemanticVersion]::new('1.1.1+2').CompareTo([SemanticVersion]::new('1.1.1+1')) -gt 0
	}
}

function Test-Pwr-AssertMinVersion {
	. pwr v -Quiet
	Invoke-PwrAssertNoThrows {
		pwr v -AssertMinimum "$env:PwrVersion"
	}
	Invoke-PwrAssertThrows {
		pwr v -AssertMinimum "9$env:PwrVersion"
	}
	Invoke-PwrAssertThrows {
		pwr v -AssertMinimum "${env:PwrVersion}9"
	}
	Invoke-PwrAssertNoThrows {
		pwr v -AssertMinimum '0.0.0'
	}
	Invoke-PwrAssertThrows {
		# Bad pattern
		pwr v -AssertMinimum '9.0'
	}
}

function Test-Pwr-FetchLocalPackageThrows {
	Invoke-PwrAssertThrows {
		pwr fetch "file:///$PSScriptRoot\pkg1"
	}
}

function Test-Pwr-RemoveLocalPackageThrows {
	Invoke-PwrAssertThrows {
		pwr rm "file:///$PSScriptRoot\pkg1"
	}
	Invoke-PwrAssertTrue {
		Test-Path "$PSScriptRoot\pkg1\.pwr"
	}
}

function Test-Pwr-GlobalVariableIsolation {
	$global:x = 'hi'
	pwr sh "file:///$PSScriptRoot\pkg1"
	Invoke-PwrAssertTrue {
		$null -eq $x
	}
	pwr exit
	Invoke-PwrAssertTrue {
		$x -eq 'hi'
	}
}

function Test-Pwr-NonGlobalVariablePassThru {
	$script:x = 'hi'
	$y = 'there'
	pwr sh "file:///$PSScriptRoot\pkg1"
	Invoke-PwrAssertTrue {
		$x -eq 'hi'
		$y -eq 'there'
	}
	pwr exit
	Invoke-PwrAssertTrue {
		$x -eq 'hi'
		$y -eq 'there'
	}
}

function Test-Pwr-PackageProcessingBeforeShellInit {
	Invoke-PwrAssertThrows {
		pwr sh "does-not-exist"
	}
	Invoke-PwrAssertTrue {
		$null -eq $env:InPwrShell
	}
}

function Test-Pwr-ShellVariableDeclaration {
	pwr sh "file:///$PSScriptRoot\pkg1"
	Invoke-PwrAssertTrue {
		(Get-Variable 'testvar').Value -eq 'foobar'
	}
}

function Test-Pwr-LoadPackageOutSession {
	pwr load "file:///$PSScriptRoot\pkg2"
	Invoke-PwrAssertTrue {
		(example2) -eq 'buzzbazz2'
	}
	pwr sh "file:///$PSScriptRoot\pkg1"
	Invoke-PwrAssertTrue {
		(example1) -eq 'buzzbazz1'
	}
	Invoke-PwrAssertThrows {
		(example2) -eq 'buzzbazz2'
	}
	pwr exit
	Invoke-PwrAssertTrue {
		(example2) -eq 'buzzbazz2'
	}
}

function Test-Pwr-LoadPackageInSession {
	pwr sh "file:///$PSScriptRoot\pkg1"
	pwr load "file:///$PSScriptRoot\pkg2"
	Invoke-PwrAssertTrue {
		(example2) -eq 'buzzbazz2'
	}
	Invoke-PwrAssertTrue {
		(example1) -eq 'buzzbazz1'
	}
	pwr exit
	Invoke-PwrAssertThrows {
		(example2) -eq 'buzzbazz2'
	}
}

function Test-Pwr-ShellEnvPath {
	$_path = $env:path
	pwr sh "file:///$PSScriptRoot\pkg1"
	Invoke-PwrAssertTrue {
		(example1) -eq 'buzzbazz1'
	}
	Invoke-PwrAssertTrue {
		$env:path -ne $_path
	}
	pwr exit
	Invoke-PwrAssertTrue {
		$env:path -eq $_path
	}
}

function Test-Pwr-ShellEnvOther {
	pwr sh "file:///$PSScriptRoot\pkg1"
	Invoke-PwrAssertTrue {
		$env:any -eq 'thing'
	}
}

function Test-Pwr-ShellGetPkg {
	pwr sh pwr; pwr exit
	Invoke-PwrAssertTrue {
		$LastExitCode -eq 0
	}
}

function Test-Pwr-AltConfig {
	pwr sh "file:///$PSScriptRoot\pkg3 < alt"
	Invoke-PwrAssertTrue {
		$env:any -eq 'bazzy'
	}
}

function Test-Pwr-DefaultConfig {
	pwr sh "file:///$PSScriptRoot\pkg3"
	Invoke-PwrAssertTrue {
		$env:any -eq 'buzzy'
	}
}

function Test-Pwr-Run {
	pwr -run print
	Invoke-PwrAssertTrue {
		$global:LastExitCode -eq 2
	}
}

function Test-Pwr-RunWithArgs {
	pwr -run set, 1, 2, 3
	Invoke-PwrAssertTrue {
		$LastExitCode -eq 2
	}
}

function Test-Pwr-RunWithDefaultArgs {
	pwr -run setA
	Invoke-PwrAssertTrue {
		$LastExitCode -eq 2
	}
}

function Test-Pwr-RunPwr {
	pwr -run testPwr
	Invoke-PwrAssertTrue {
		$LastExitCode -eq 0
	}
}

###### Test Runner ######

function Invoke-PwrTest($fn) {
	try {
		Invoke-Expression $fn | Out-Null
		Write-Host -ForegroundColor Green "[PASSED] $fn"
	} catch {
		$env:PwrTestFail = $true
		Write-Host -ForegroundColor Red "[FAILED] $fn`r`n`t> $_`r`n`t$($_.ScriptStackTrace.Split("`n")  -join "`r`n`t")"
	} finally {
		pwr exit -Silent
	}
}

switch ($TestName) {
	'' {
		Get-Item function:Test-Pwr-* | ForEach-Object {
			Invoke-PwrTest $_.Name
		}
	}
	Default {
		Invoke-PwrTest "Test-Pwr-$TestName"
	}
}

if ($env:PwrTestFail) {
	$env:PwrTestFail = $null
	Write-Host -ForegroundColor Red "Test failure"
	exit 1
} else {
	exit 0
}