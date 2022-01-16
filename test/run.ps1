$env:Path = "$PSScriptRoot\..\src;$env:Path"

function Invoke-PwrAssertTrue($block) {
	$r = Invoke-Command -ScriptBlock $block
	if (-not $r) {
		Write-Error "Assertion Failed: $block"
	}
}

function Invoke-PwrAssertThrows($block) {
	try {
		Invoke-Command -ScriptBlock $block | Out-Null
		Write-Error "Assertion Failed to Throw: $block"
	} catch { }
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

function Test-Pwr-ShellEnvPath {
	$_path = $env:path
	pwr sh "file:///$PSScriptRoot\pkg1"
	Invoke-PwrAssertTrue {
		(example) -eq 'buzzbazz'
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

Get-Item function:Test-Pwr-* | ForEach-Object {
	$fn = $_.Name
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

if ($env:PwrTestFail) {
	$env:PwrTestFail = $null
	Write-Error "Test failure"
}