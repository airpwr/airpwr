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
					function AirpowerTest1 {
						return 2
					}
					function AirpowerTest2 {
						param (
							[int]$X,
							[int]$Y
						)
						return $X - $Y
					}
					function AirpowerTest3 {
						param (
							[string]$Option = 'hello'
						)
						return $Option
					}
					function AirpowerTest4 {
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
			function AirpowerTest {
				return 2
			}
			Mock FindConfig { }
		}
		AfterAll {
			Remove-Item 'function:AirpowerTest'
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
			& $pwr 'exec' -script { 'hi' }
			Should -Invoke -CommandName 'Invoke-AirpowerExec' -Exactly -Times 1 -ParameterFilter { $Packages.Count -eq 0 -and $Script.ToString() -eq " 'hi' " }
		}
		It 'Exec With Packages' {
			& $pwr 'exec' 'a', 'b' { 'hi' }
			Should -Invoke -CommandName 'Invoke-AirpowerExec' -Exactly -Times 1 -ParameterFilter { $Packages.Count -eq 2 -and $Script.ToString() -eq " 'hi' " }
		}
	}
}
