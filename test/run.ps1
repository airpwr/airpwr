param (
	[string]$TestName
)

$PowerShell = (Get-Process -Id $PID).Path

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
		throw
	}
}

###### Test Helpers ######

function Invoke-PwrWithTempHome($block) {
	$private:TempDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid())
	New-Item -ItemType Directory -Path $TempDirectory
	$private:PreviousPwrHome = $env:PwrHome
	try {
		$env:PwrHome = $TempDirectory
		&$block
	} finally {
		$env:PwrHome = $PreviousPwrHome
		Remove-Item -Recurse -Force -Path $TempDirectory | Out-Null
	}
}

function Invoke-PwrSetPackages {
	param(
		[string]$Repo,
		$Packages
	)
	$private:Hash = &$script:PowerShell -NoProfile -Command {
		param($Repo)
		. pwr v -Quiet
		Get-StringHash $Repo
	} -args $Repo
	$private:Cache = @{}
	foreach ($P in $Packages) {
		if ($P.Pwr) {
			New-Item -Force -ItemType Directory -Path "$env:PwrHome\pkg\$($P.Name)-$($P.Version)"
			Set-Content "$env:PwrHome\pkg\$($P.Name)-$($P.Version)\.pwr" $P.Pwr
		}
		$Cache.($P.Name) = @($Cache.($P.Name)) + $P.Version | Sort-Object -Descending
	}
	New-Item -Force -ItemType Directory -Path "$env:PwrHome\cache"
	[IO.File]::WriteAllText("$env:PwrHome\cache\$Hash", ($Cache | ConvertTo-Json -Compress))
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
	$Version = &$script:PowerShell -NoProfile -Command {
		. pwr v -Quiet
		$env:PwrVersion
	}
	Invoke-PwrAssertNoThrows {
		pwr v -AssertMinimum "$Version"
	}
	Invoke-PwrAssertThrows {
		pwr v -AssertMinimum "9$Version"
	}
	Invoke-PwrAssertThrows {
		pwr v -AssertMinimum "${Version}9"
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

function Test-Pwr-ShellInit {
	pwr sh
	Invoke-PwrAssertTrue {
		(curl.exe) -eq 'buzzbazz1'
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

function Test-Pwr-List {
	Invoke-PwrWithTempHome {
		$Repo = 'https://fake.repo/v2/pwr'
		$Packages = @(
			@{Name = 'pkg-1'; Version = '1.0.0'},
			@{Name = 'pkg-1'; Version = '1.1.0'; Pwr = '{}'},
			@{Name = 'pkg-2'; Version = '1.2.0'},
			@{Name = 'pkg-3'; Version = '1.3.0'; Pwr = '{}'}
		)
		Invoke-PwrSetPackages $Repo $Packages

		# List: all packages listed
		$ListInstalled = pwr -Offline -Repositories $Repo list | Out-String
		Invoke-PwrAssertTrue { $ListInstalled.Contains('1.0.0') }
		Invoke-PwrAssertTrue { $ListInstalled.Contains('1.1.0') }
		Invoke-PwrAssertTrue { $ListInstalled.Contains('1.2.0') }
		Invoke-PwrAssertTrue { $ListInstalled.Contains('1.3.0') }

		# List installed: pkg-1:1.1.0, pkg-3:1.3.0 listed
		$ListInstalled = pwr -Offline -Repositories $Repo list -Installed | Out-String
		Invoke-PwrAssertTrue { -not $ListInstalled.Contains('1.0.0') }
		Invoke-PwrAssertTrue { $ListInstalled.Contains('1.1.0') }
		Invoke-PwrAssertTrue { -not $ListInstalled.Contains('1.2.0') }
		Invoke-PwrAssertTrue { $ListInstalled.Contains('1.3.0') }
	}
}

function Test-Pwr-Remove {
	Invoke-PwrWithTempHome {
		$Repo = 'https://fake.repo/v2/pwr'
		$Packages = @(
			@{Name = 'pkg-1'; Version = '1.0.0'; Pwr = '{}'},
			@{Name = 'pkg-1'; Version = '1.1.0'; Pwr = '{}'}
		)
		Invoke-PwrSetPackages $Repo $Packages

		# Baseline: all versions installed
		$ListInstalled = pwr -Offline -Repositories $Repo list -Installed | Out-String
		Invoke-PwrAssertTrue { $ListInstalled.Contains('1.0.0') }
		Invoke-PwrAssertTrue { $ListInstalled.Contains('1.1.0') }

		# Remove pkg-1:1.1.0
		pwr -Offline -Repositories $Repo rm pkg-1:1.1.0
		$ListInstalled = pwr -Offline -Repositories $Repo list -Installed | Out-String
		Invoke-PwrAssertTrue { $ListInstalled.Contains('1.0.0') }
		Invoke-PwrAssertTrue { -not $ListInstalled.Contains('1.1.0') }
	}
}

function Test-Pwr-PruneLatest {
	Invoke-PwrWithTempHome {
		$Repo = 'https://fake.repo/v2/pwr'
		$Packages = @(
			@{Name = 'pkg-1'; Version = '1.0.0'; Pwr = '{}'},
			@{Name = 'pkg-1'; Version = '1.1.0'; Pwr = '{}'}
		)
		Invoke-PwrSetPackages $Repo $Packages

		# Baseline: all versions installed
		$ListInstalled = pwr -Offline -Repositories $Repo list -Installed | Out-String
		Invoke-PwrAssertTrue { $ListInstalled.Contains('1.0.0') }
		Invoke-PwrAssertTrue { $ListInstalled.Contains('1.1.0') }

		# Prune: remove all versions except latest
		pwr -Offline -Repositories $Repo load pkg-1
		pwr -Offline -Repositories $Repo prune
		$ListInstalled = pwr -Offline -Repositories $Repo list -Installed | Out-String
		Invoke-PwrAssertTrue { -not $ListInstalled.Contains('1.0.0') }
		Invoke-PwrAssertTrue { $ListInstalled.Contains('1.1.0') }
	}
}

function Test-Pwr-PruneVersion {
	Invoke-PwrWithTempHome {
		$Repo = 'https://fake.repo/v2/pwr'
		$Packages = @(
			@{Name = 'pkg-1'; Version = '0.9.0'; Pwr = '{}'},
			@{Name = 'pkg-1'; Version = '1.0.0'; Pwr = '{}'},
			@{Name = 'pkg-1'; Version = '1.1.0'; Pwr = '{}'},
			@{Name = 'pkg-1'; Version = '1.2.0'; Pwr = '{}'}
		)
		Invoke-PwrSetPackages $Repo $Packages

		# Baseline: all versions installed
		$ListInstalled = pwr -Offline -Repositories $Repo list -Installed | Out-String
		Invoke-PwrAssertTrue { $ListInstalled.Contains('0.9.0') }
		Invoke-PwrAssertTrue { $ListInstalled.Contains('1.0.0') }
		Invoke-PwrAssertTrue { $ListInstalled.Contains('1.1.0') }
		Invoke-PwrAssertTrue { $ListInstalled.Contains('1.2.0') }

		# Prune: remove all versions except latest, 1.0
		pwr -Offline -Repositories $Repo load pkg-1:1.0
		pwr -Offline -Repositories $Repo prune
		$ListInstalled = pwr -Offline -Repositories $Repo list -Installed | Out-String
		Invoke-PwrAssertTrue { -not $ListInstalled.Contains('0.9.0') }
		Invoke-PwrAssertTrue { $ListInstalled.Contains('1.0.0') }
		Invoke-PwrAssertTrue { -not $ListInstalled.Contains('1.1.0') }
		Invoke-PwrAssertTrue { $ListInstalled.Contains('1.2.0') }
	}
}

###### Test Runner ######

if ($MyInvocation.InvocationName -eq '.' -or $MyInvocation.Line -eq '') {
	exit # Exit if the script was dot-sourced
}

$ExitCode = 0

function Invoke-PwrTest($fn) {
	&$script:PowerShell -NoProfile -Command {
		param($script, $fn)
		Set-Location $(Split-Path -Parent $script)
		$env:Path = "$(Split-Path -Parent $script)\..\src;$env:Path"
		. $script

		function Invoke-Test($private:TestName) {
			try {
				Invoke-Expression $TestName | Out-Null
				Write-Host -ForegroundColor Green "[PASSED] $TestName"
			} catch {
				Write-Host -ForegroundColor Red "[FAILED] $TestName`r`n`t> $_`r`n`t$($_.ScriptStackTrace.Split("`n")  -join "`r`n`t")"
				exit 1
			}
		}

		Invoke-Test($fn)
	} -args $PSCommandPath, $fn
	if ($LASTEXITCODE -ne 0) {
		$script:ExitCode++
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

if ($ExitCode -gt 0) {
	Write-Host -ForegroundColor Red "Test failure"
	exit $ExitCode
} else {
	exit 0
}