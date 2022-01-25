param (
	[string]$TestName
)

$env:Path = "$PSScriptRoot\..\src;$env:Path"

###### Assertions ######
function Invoke-PwrAssertTrue($block) {
	Invoke-Command -ScriptBlock $block | Out-Null
	if (-not $?) {
		Write-Error "Assertion Failed: $block"
	}
}

function Invoke-PwrAssertThrows($block) {
	try {
		Invoke-Command -ScriptBlock $block | Out-Null
		Write-Error "Assertion Failed to Throw: $block"
	} catch { }
}

###### Tests ######

function Test-Pwr-BuildVersions {
	. pwr v | Out-Null
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
		[SemanticVersion]::new('1.1.1+1').CompareTo([SemanticVersion]::new('1.1.1+2')) -gt 0
	}
	Invoke-PwrAssertTrue {
		[SemanticVersion]::new('1.1.1+2').CompareTo([SemanticVersion]::new('1.1.1+1')) -lt 0
	}
}

function Test-Pwr-AssertMinVersion {
	pwr v | Out-Null
	Invoke-PwrAssertTrue {
		pwr v -AssertMinimum "$env:PwrVersion"
	}
	Invoke-PwrAssertThrows {
		pwr v -AssertMinimum "9$env:PwrVersion"
	}
	Invoke-PwrAssertThrows {
		pwr v -AssertMinimum "${env:PwrVersion}9"
	}
	Invoke-PwrAssertTrue{
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
		$x -eq $null
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

###### Test Runner ######

function Invoke-PwrTest($fn) {

	try {
		Invoke-Expression $fn | Out-Null
		Write-Host -ForegroundColor Green "[PASSED] $fn"
	} catch {
		$env:PwrTestFail = $true
		Write-Host -ForegroundColor Red "[FAILED] $fn`r`n`t> $_`r`n`t$($_.ScriptStackTrace.Split("`n")  -join "`r`n`t")"
	} finally {
		try {
			pwr exit -ErrorAction 'SilentlyContinue' | Out-Null
		} catch {}
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
	Write-Error "Test failure"
}