BeforeAll {
	. $PSCommandPath.Replace('.Tests.ps1','.ps1')
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
				$script:PwrPackages = 'a', 'b'
			}
		}
		AfterAll {
			$script:PwrPackages = $null
		}
		It 'Load Without Packages' {
			Invoke-Airpower 'load'
			Should -Invoke -CommandName 'LoadPackage' -Exactly -Times 1 -ParameterFilter { $pkg.Package -eq 'a' }
			Should -Invoke -CommandName 'LoadPackage' -Exactly -Times 1 -ParameterFilter { $pkg.Package -eq 'b' }
		}
		It 'Load With Package' {
			Invoke-Airpower 'load' 'x'
			Should -Invoke -CommandName 'LoadPackage' -Exactly -Times 1 -ParameterFilter { $pkg.Package -eq 'x' }
			Should -Invoke -CommandName 'LoadPackage' -Exactly -Times 0 -ParameterFilter { $pkg.Package -eq 'a' }
			Should -Invoke -CommandName 'LoadPackage' -Exactly -Times 0 -ParameterFilter { $pkg.Package -eq 'b' }
		}
		It 'Load Mixed Args' {
			Invoke-Airpower 'load' 'x', 'z' 'y'
			Should -Invoke -CommandName 'LoadPackage' -Exactly -Times 1 -ParameterFilter { $pkg.Package -eq 'x' }
			Should -Invoke -CommandName 'LoadPackage' -Exactly -Times 1 -ParameterFilter { $pkg.Package -eq 'z' }
			Should -Invoke -CommandName 'LoadPackage' -Exactly -Times 1 -ParameterFilter { $pkg.Package -eq 'y' }
		}
	}
	Context 'Run' {
		BeforeAll {
			Mock FindConfig {
				return {
					function PwrTest1 {
						return 2
					}
					function PwrTest2 {
						param (
							[int]$X,
							[int]$Y
						)
						return $X - $Y
					}
					function PwrTest3 {
						return 2
					}
				}
			}
		}
		It 'Function Without Params' {
			$res = Invoke-Airpower 'run' 'test1'
			$res | Should -Be 2
		}
		It 'Function With Param Splat' {
			$p = @{X=7; Y=3}
			$res = Invoke-Airpower 'run' 'test2' @p
			$res | Should -Be 4
		}
		It 'Function With Param Position' {
			$res = Invoke-Airpower 'run' 'test2' 9 2
			$res | Should -Be 7
		}
		It 'Function With Param Flag' {
			$res = Invoke-Airpower 'run' 'test2' -X 4 -Y 9
			$res | Should -Be -5
		}
	}
}