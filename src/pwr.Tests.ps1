BeforeAll {
	. $PSCommandPath.Replace('.Tests.ps1', '.ps1')
	$script:ModulePath = $env:PSModulePath
	$env:PSModulePath = $null
	Remove-Module Airpower -ErrorAction SilentlyContinue
	$script:pwr = (Get-Item 'function:Invoke-Airpower').ScriptBlock
}

AfterAll {
	$env:PSModulePath = $ModulePath
}

Describe 'Invoke-Airpower' {
	Context 'Load' {
		BeforeAll {
			Mock ResolvePackage {
				param (
					[Parameter(Mandatory, ValueFromPipeline)]
					[string]$Ref
				)
				return @{Package = $ref}
			}
			Mock LoadPackage { }
			Mock FindConfig {
				$script:AirpowerPackages = 'a', 'b'
			}
		}
		AfterAll {
			$script:AirpowerPackages = $null
		}
		It 'Load Without Packages' {
			& $pwr 'load'
			Should -Invoke -CommandName 'LoadPackage' -Exactly -Times 1 -ParameterFilter { $pkg.Package -eq 'a' }
			Should -Invoke -CommandName 'LoadPackage' -Exactly -Times 1 -ParameterFilter { $pkg.Package -eq 'b' }
		}
		It 'Load With Package' {
			& $pwr 'load' 'x'
			Should -Invoke -CommandName 'LoadPackage' -Exactly -Times 1 -ParameterFilter { $pkg.Package -eq 'x' }
			Should -Invoke -CommandName 'LoadPackage' -Exactly -Times 0 -ParameterFilter { $pkg.Package -eq 'a' }
			Should -Invoke -CommandName 'LoadPackage' -Exactly -Times 0 -ParameterFilter { $pkg.Package -eq 'b' }
		}
		It 'Load Multiple' {
			& $pwr 'load' 'x', 'z', 'y'
			Should -Invoke -CommandName 'LoadPackage' -Exactly -Times 1 -ParameterFilter { $pkg.Package -eq 'x' }
			Should -Invoke -CommandName 'LoadPackage' -Exactly -Times 1 -ParameterFilter { $pkg.Package -eq 'z' }
			Should -Invoke -CommandName 'LoadPackage' -Exactly -Times 1 -ParameterFilter { $pkg.Package -eq 'y' }
		}
	}
	Context 'Run Config' {
		BeforeAll {
			Mock FindConfig {
				return {
					function AirpowerRunTest1 {
						return 2
					}
					function AirpowerRunTest2 {
						param (
							[int]$X,
							[int]$Y
						)
						return $X - $Y
					}
					function AirpowerRunTest3 {
						param (
							[string]$Option = 'hello'
						)
						return $Option
					}
					function AirpowerRunTest4 {
						param (
							[switch]$Enabled
						)
						return $Enabled
					}
				}
			}
		}
		It 'Function Without Params' {
			$res = & $pwr 'run' 'test1'
			$res | Should -Be 2
		}
		It 'Function With Param Splat' {
			$p = @{X=7; Y=3}
			$res = & $pwr 'run' 'test2' @p
			$res | Should -Be 4
		}
		It 'Function With Param Position' {
			$res = & $pwr 'run' 'test2' 9 2
			$res | Should -Be 7
		}
		It 'Function With Param Position Extra' {
			$res = & $pwr 'run' 'test2' 9 2 11
			$res | Should -Be 7
		}
		It 'Function With Param Flag' {
			$res = & $pwr 'run' 'test2' -X:4 -Y 9
			$res | Should -Be -5
		}
		It 'Function With Param Flag Expression' {
			$res = & $pwr 'run' 'test2' -X:(5 + 1 - 3) -Y 9
			$res | Should -Be -6
		}
		It 'Function With Param Default' {
			$res = & $pwr 'run' 'test3' world
			$res | Should -Be 'world'
		}
		It 'Function With Param Switch' {
			$res = & $pwr 'run' 'test4' -enabled
			$res | Should -Be $true
		}
		It 'Function With Param Switch Explicit' {
			$res = & $pwr 'run' 'test4' -enabled:$true
			$res | Should -Be $true
		}
		It 'Function With Param Switch Explicit False' {
			$res = & $pwr 'run' 'test4' -enabled:$false
			$res | Should -Be $false
		}
	}
	Context 'Run Without Config' {
		BeforeAll {
			function AirpowerRunTest {
				return 2
			}
			Mock FindConfig { }
		}
		AfterAll {
			Remove-Item 'function:AirpowerRunTest'
		}
		It 'Function Without Params' {
			$res = & $pwr 'run' 'test'
			$res | Should -Be 2
		}
	}
	Context 'ErrorAction' {
		BeforeAll {
			function SomeFn { }
			Mock SomeFn { }
			Mock FindConfig { }
		}
		It 'Stops' {
			try {
				& $pwr 'load' -ErrorAction Stop
				SomeFn
			} catch {
				'expect error'
			} finally {
				Should -Invoke SomeFn -Times 0 -Exactly
			}
		}
		It 'Continues' {
			try {
				& $pwr 'load' -ErrorAction SilentlyContinue
				SomeFn
			} finally {
				Should -Invoke SomeFn -Times 1 -Exactly
			}
		}
	}
	Context 'Exec' {
		BeforeAll {
			Mock Invoke-AirpowerExec { }
		}
		It 'Exec Without Packages' {
			& $pwr 'exec' -ScriptBlock { 'hi' }
			Should -Invoke -CommandName 'Invoke-AirpowerExec' -Exactly -Times 1 -ParameterFilter { $Packages.Count -eq 0 -and $ScriptBlock.ToString() -eq " 'hi' " }
		}
		It 'Exec With Packages' {
			& $pwr 'exec' 'a', 'b' { 'hi' }
			Should -Invoke -CommandName 'Invoke-AirpowerExec' -Exactly -Times 1 -ParameterFilter { $Packages.Count -eq 2 -and $ScriptBlock.ToString() -eq " 'hi' " }
		}
		It 'Exec With Default Script' {
			& $pwr 'exec' 'a', 'b'
			Should -Invoke -CommandName 'Invoke-AirpowerExec' -Exactly -Times 1 -ParameterFilter { $Packages.Count -eq 2 }
		}
	}
	Context 'Exec Local' {
		It 'Default Config' {
			$v = & $pwr 'exec' 'file:///test/pkg' -ScriptBlock { foo }
			$v | Should -Be 'bar'
		}
		It 'With Config' {
			$v = & $pwr 'exec' 'file:///test/pkg < somecfg' -ScriptBlock { buzz }
			$v | Should -Be 'bazz'
		}
	}
}

Describe 'Invoke-AirpowerRun' {
	Context 'Config Packages' {
		BeforeAll {
			Mock FindConfig {
				return {
					$AirpowerPackages = 'go'
					$AirpowerPackages | Out-Null
					function AirpowerRunTest { }
				}
			}
			Mock ResolvePackage {
				return @{Package = $Ref}
			}
			Mock ExecuteScript { 7 }
		}
		It 'Defaults' {
			$v = Invoke-AirpowerRun -FnName 'test' -ScriptBlock { 'hi' }
			$v | Should -Be 7
			Should -Invoke -CommandName 'ExecuteScript' -Exactly -Times 1 -ParameterFilter { $Pkgs.Count -eq 1 -and $Pkgs[0].Package -eq 'go' }
		}
	}
}

if ($env:CI) {
	Describe 'CI' {
		BeforeEach {
			[Db]::Init()
			$ProgressPreference = 'SilentlyContinue'
		}
		It 'Pull and Exec' {
			& $pwr 'exec' 'python' { python --version } -ErrorAction Stop
		}
	}
}

Describe 'CheckForUpdates' {
	Context "Throws" {
		BeforeEach {
			Mock HttpSend {
				throw "offline"
			}
		}
		It 'Writes Debug' {
			{ CheckForUpdates } | Should -Not -Throw
		}
	}
	Context "Version" {
		BeforeAll {
			Mock Import-PowerShellDataFile {
				return @{
					ModuleVersion = '1.2.3'
				}
			}
			Mock HttpRequest {
				return [Net.Http.HttpRequestMessage]::new()
			}
			Mock HttpSend {
				$resp = [Net.Http.HttpResponseMessage]::new()
				$resp.Headers.Add('Location', '/packages/airpower/1.2.4')
				return $resp
			}
			Mock WriteHost { }
		}
		It 'Writes Host' {
			CheckForUpdates
			Should -Invoke -CommandName 'WriteHost' -Exactly -Times 1
		}
	}
}
