BeforeAll {
	. $PSCommandPath.Replace('.Tests.ps1', '.ps1')
}

Describe 'ExecuteScript' {
	Context 'Example Packages' {
		BeforeAll {
			Mock ResolvePackageDigest {
				param (
					[Parameter(Mandatory, ValueFromPipeline)]
					[Collections.Hashtable]$Pkg
				)
				return @{
					'somepkg' = 'sha256-1'
					'anotherpkg' = 'sha256-2'
				}[$Pkg.Package]
			}
			Mock GetPackageDefinition {
				param (
					[Parameter(Mandatory, ValueFromPipeline)]
					[string]$Digest
				)
				return @{
					'sha256-1' = @{
						Env = @{
							'var1' = 'val'
							'path' = 'zzz'
						}
					}
					'sha256-2' = @{
						Env = @{
							'path' = 'fizz'
							'foo' = 'bar'
						}
					}
				}[$Digest]
			}
			function SomeFn { }
			Mock SomeFn { }
		}
		AfterAll {
			Remove-Item 'env:var1' -Force -ErrorAction SilentlyContinue
			Remove-Item 'env:foo' -Force -ErrorAction SilentlyContinue
		}
		It 'Configures' {
			$SysPath = "$env:SYSTEMROOT;$env:SYSTEMROOT\System32;$PSHOME"
			$env:Path | Should -Not -BeLike '*zzz;*'
			$env:var1 | Should -BeNullOrEmpty
			ExecuteScript -Pkgs @{
				Package = 'somepkg'
				Tag = @{ Latest = $true }
				Config = 'default'
			} -ScriptBlock {
				SomeFn
				$yyy = '123'
				$yyy | Should -Not -BeNullOrEmpty
				$script:xxx = '987'
				$script:xxx | Should -Not -BeNullOrEmpty
				$env:Path | Should -Be "zzz;$SysPath"
				$env:var1 | Should -Be 'val'
			}
			Should -Invoke SomeFn -Times 1 -Exactly
			$env:Path | Should -Not -BeLike '*zzz;*'
			$env:var1 | Should -Be 'val' # env vars persist in session
			$xxx | Should -Be '987' # script vars persist in session
			$yyy | Should -BeNullOrEmpty # local vars do not persist in session
		}
		It 'Nests' {
			$SysPath = "$env:SYSTEMROOT;$env:SYSTEMROOT\System32;$PSHOME"
			ExecuteScript -Pkgs @{
				Package = 'somepkg'
				Tag = @{ Latest = $true }
				Config = 'default'
			} -ScriptBlock {
				ExecuteScript -Pkgs @{
					Package = 'anotherpkg'
					Tag = @{ Latest = $true }
					Config = 'default'
				} -ScriptBlock {
					SomeFn
					$env:Path | Should -Be "fizz;$SysPath"
					$env:foo | Should -Be 'bar'
				}
				$env:Path | Should -Be "zzz;$SysPath"
			}
			Should -Invoke SomeFn -Times 1 -Exactly
		}
	}
}