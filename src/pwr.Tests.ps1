BeforeAll {
	. $PSCommandPath.Replace('.Tests.ps1','.ps1')
}

Describe 'Invoke-Airpower' {
	Context 'Project File' {
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
		It 'Blank Load Has Packages' {
			Invoke-Airpower 'load'
			Should -Invoke -CommandName 'LoadPackage' -Exactly -Times 1 -ParameterFilter { $pkg.Package -eq 'a' }
			Should -Invoke -CommandName 'LoadPackage' -Exactly -Times 1 -ParameterFilter { $pkg.Package -eq 'b' }
		}
		It 'Load Has Package' {
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
}