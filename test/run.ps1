$env:Path = "$PSScriptRoot\..\src;$env:Path"

function Invoke-PwrAssertion($block) {
	$r = Invoke-Command -ScriptBlock $block
	if (-not $r) {
		Write-Error "Assertion Failed: $block"
	}
}

function Test-Pwr-GlobalVariableIsolation {
	$global:x = 'hi'
	pwr sh "file:///$PSScriptRoot\pkg1"
	Invoke-PwrAssertion {
		$x -eq $null
	}
	pwr exit
	Invoke-PwrAssertion {
		$x -eq 'hi'
	}
}

function Test-Pwr-ShellVariableDeclaration {
	pwr sh "file:///$PSScriptRoot\pkg1"
	Invoke-PwrAssertion {
		(Get-Variable 'testvar').Value -eq 'foobar'
	}
}

function Test-Pwr-ShellEnvPath {
	pwr sh "file:///$PSScriptRoot\pkg1"
	Invoke-PwrAssertion {
		(example) -eq 'buzzbazz'
	}
}

Get-Item function:Test-Pwr-* | ForEach-Object {
	$fn = $_.Name
	try {
		Invoke-Expression $fn | Out-Null
		Write-Host -ForegroundColor Green "[PASSED] $fn"
	} catch {
		$failed = $true
		Write-Host -ForegroundColor Red "[FAILED] $fn`r`n`t> $_`r`n`t$($_.ScriptStackTrace.Split("`n")  -join "`r`n`t")"
	} finally {
		try {
			pwr exit -ErrorAction 'SilentlyContinue' | Out-Null
		} catch {}
	}
}

if ($failed) {
	Write-Error "Test failure"
}