BeforeAll {
	. $PSCommandPath.Replace('.Tests.ps1', '.ps1')
	Mock WriteHost {}
}

Describe 'InstallPackage' {
	Context 'From Nothing' {
		BeforeAll {
			Mock Test-Path {
				$false
			}
		}
		It 'Installs' {
			$pkg = @{
				Package = 'somepkg'
				Tag = @{
					Latest = $true
				}
				Digest = 'fde54e65gd4678'
				Size = 982365234
			}
			$db, $null = $pkg | InstallPackage
			$db.pkgdb.somepkg.latest | Should -Be 'fde54e65gd4678'
			$db.metadatadb.fde54e65gd4678.refcount | Should -Be 1
			$db.metadatadb.fde54e65gd4678.size | Should -Be 982365234
		}
	}
	Context 'New Tag, Same Digest' {
		BeforeAll {
			Mock GetPwrDB {
				@{
					'pkgdb' = @{
						'somepkg' = @{
							'latest' = 'fde54e65gd4678'
						}
					}
					'metadatadb' = @{
						'fde54e65gd4678' = @{
							RefCount = 1
							Size = 293874
						}
					}
				}
			}
		}
		It 'Replaces' {
			$pkg = @{
				Package = 'somepkg'
				Tag = @{
					Major = 1
					Minor = 2
				}
				Digest = 'fde54e65gd4678'
				Size = 982365234
			}
			$db, $null = $pkg | InstallPackage
			$db.pkgdb.somepkg.latest | Should -Be 'fde54e65gd4678'
			$db.pkgdb.somepkg.'1.2' | Should -Be 'fde54e65gd4678'
			$db.metadatadb.fde54e65gd4678.refcount | Should -Be 2
			$db.metadatadb.fde54e65gd4678.size | Should -Be 293874
		}
	}
	Context 'Same Tag, New Digest' {
		BeforeAll {
			Mock GetPwrDB {
				@{
					'pkgdb' = @{
						'somepkg' = @{
							'latest' = 'fde54e65gd4678'
						}
					}
					'metadatadb' = @{
						'fde54e65gd4678' = @{
							RefCount = 1
							Size = 293874
						}
					}
				}
			}
		}
		It 'Replaces' {
			$pkg = @{
				Package = 'somepkg'
				Tag = @{
					Latest = $true
				}
				Digest = 'abc123'
				Size = 999123
			}
			$db, $null = $pkg | InstallPackage
			$db.pkgdb.somepkg.Count | Should -Be 2
			$db.pkgdb.somepkg.latest | Should -Be 'abc123'
			$db.pkgdb.somepkg.fde54e65gd4678 | Should -Be $null
			$db.metadatadb.fde54e65gd4678.refcount | Should -Be 0
			$db.metadatadb.fde54e65gd4678.size | Should -Be 293874
			$db.metadatadb.abc123.refcount | Should -Be 1
			$db.metadatadb.abc123.size | Should -Be 999123
		}
	}
	Context 'From RefCount 0' {
		BeforeAll {
			Mock GetPwrDB {
				@{
					'pkgdb' = @{
						'somepkg' = @{
							'fde54e65gd4678' = $null
						}
					}
					'metadatadb' = @{
						'fde54e65gd4678' = @{
							RefCount = 0
							Size = 293874
						}
					}
				}
			}
		}
		It 'Installs' {
			$pkg = @{
				Package = 'somepkg'
				Tag = @{
					Latest = $true
				}
				Digest = 'fde54e65gd4678'
			}
			$db, $null = $pkg | InstallPackage
			$db.pkgdb.somepkg.Count | Should -Be 1
			$db.pkgdb.somepkg.latest | Should -Be 'fde54e65gd4678'
			$db.metadatadb.fde54e65gd4678.refcount | Should -Be 1
			$db.metadatadb.fde54e65gd4678.size | Should -Be 293874
		}
	}
}

Describe 'UninstallPackage' {
	Context 'From 2+' {
		BeforeAll {
			Mock GetPwrDB {
				@{
					'pkgdb' = @{
						'somepkg' = @{
							'latest' = 'fde54e65gd4678'
							'1.2' = 'fde54e65gd4678'
						}
					}
					'metadatadb' = @{
						'fde54e65gd4678' = @{
							RefCount = 2
							Size = 293874
						}
					}
				}
			}
		}
		It 'Decrements' {
			$pkg = @{
				Package = 'somepkg'
				Tag = @{
					Major = 1
					Minor = 2
				}
			}
			$db, $null, $null = $pkg | UninstallPackage
			$db.pkgdb.somepkg.Count | Should -Be 1
			$db.pkgdb.somepkg.latest | Should -Be 'fde54e65gd4678'
			$db.metadatadb.fde54e65gd4678.refcount | Should -Be 1
		}
	}
	Context 'From 1' {
		BeforeAll {
			Mock GetPwrDB {
				@{
					'pkgdb' = @{
						'somepkg' = @{
							'latest' = 'fde54e65gd4678'
						}
					}
					'metadatadb' = @{
						'fde54e65gd4678' = @{
							RefCount = 1
							Size = 293874
						}
					}
				}
			}
		}
		It 'Removes' {
			$pkg = @{
				Package = 'somepkg'
				Tag = @{
					Latest = $true
				}
			}
			$db, $null, $null = $pkg | UninstallPackage
			$db.pkgdb.somepkg | Should -Be $null
			$db.metadatadb.ContainsKey('fde54e65gd4678') | Should -BeFalse
		}
	}
}

Describe 'PrunePackages' {
	Context 'From DB' {
		BeforeAll {
			Mock GetPwrDB {
				@{
					'pkgdb' = @{
						'somepkg' = @{
							'fde54e65gd4678' = $null
							'latest' = 'abc'
						}
						'another' = @{
							'e340857fffc987' = $null
							'latest' = 'xyz'
						}
						'and-another' = @{
							'ff7d401461e301' = $null
							'latest' = 'ijk'
						}
					}
					'metadatadb' = @{
						'abc' = @{RefCount = 1}
						'xyz' = @{RefCount = 1}
						'ijk' = @{RefCount = 1}
						'fde54e65gd4678' = @{RefCount = 0; Size = 3}
						'e340857fffc987' = @{RefCount = 0; RefLostAt = ((Get-Date) - (New-TimeSpan -Days 8)) | Get-Date -Format FileDateTimeUniversal; Size = 5}
						'ff7d401461e301' = @{RefCount = 0; RefLostAt = ((Get-Date) - (New-TimeSpan -Days 6)) | Get-Date -Format FileDateTimeUniversal; Size = 7}
					}
				}
			}
		}
		It 'Prunes' {
			$db, $pruned = UninstallOrphanedPackages (New-TimeSpan -Days 7)
			$pruned.Count | Should -Be 2
			$db.pkgdb.somepkg.Count | Should -Be 1
			$db.pkgdb.somepkg.latest | Should -Be 'abc'
			$db.pkgdb.another.Count | Should -Be 1
			$db.pkgdb.another.latest | Should -Be 'xyz'
			$db.metadatadb.count | Should -Be 4
			$db.metadatadb.fde54e65gd4678 | Should -Be $null
			$db.metadatadb.e340857fffc987 | Should -Be $null
			$db.metadatadb.ff7d401461e301.refcount | Should -Be 0
			$db.metadatadb.ff7d401461e301.size | Should -Be 7
		}
	}
	Context 'Last Package' {
		BeforeAll {
			Mock GetPwrDB {
				@{
					'pkgdb' = @{
						'somepkg' = @{
							'fde54e65gd4678' = $null
						}
					}
					'metadatadb' = @{
						'fde54e65gd4678' = @{RefCount = 0; Size = 3}
					}
				}
			}
		}
		It 'Prunes' {
			$db, $pruned = UninstallOrphanedPackages
			$pruned.Count | Should -Be 1
			$db.pkgdb.somepkg | Should -Be $null
			$db.metadatadb.fde54e65gd4678 | Should -Be $null
		}
	}
}

Describe 'GetLocalPackages' {
	Context 'From Nothing' {
		BeforeAll {
			Mock Test-Path {
				$false
			}
		}
		It 'Blank' {
			$pkgs = GetLocalPackages
			$pkgs | Should -HaveCount 1
			$pkgs[0].Package | Should -Be $null
			$pkgs[0].Tag | Should -Be $null
			$pkgs[0].Digest | Should -Be $null
			$pkgs[0].Size | Should -Be $null
		}
	}
	Context 'From DB' {
		BeforeAll {
			$digest = 'sha256:41d9d6d55caf3de74832ac7d7f4226180b305e1d76f00f72dde2581e7f1e4b94'
			Mock GetPwrDB {
				@{
					'pkgdb' = @{
						'somepkg' = @{
							'latest' = $digest
						}
					}
					'metadatadb' = @{
						"$digest" = @{
							RefCount = 1
							Size = 293874
						}
					}
				}
			}
		}
		It 'Shows' {
			$pkgs = GetLocalPackages
			$pkgs | Should -HaveCount 1
			$pkgs[0].Package | Should -Be 'somepkg'
			$pkgs[0].Tag | Should -Be 'latest'
			$pkgs[0].Digest.Sha256 | Should -Be $digest
			$pkgs[0].Size.Bytes | Should -Be 293874
		}
	}
}

Describe 'PullPackage' {
	Context 'Ref' {
		$script:testRoot = (Resolve-Path "$PSScriptRoot\..\test").Path
		$script:testPath = "$testRoot\pull_package_test"
		BeforeAll {
			Mock ResolveRemoteRef { 'none' }
			Mock OutPwrDB {}
			Mock GetManifest { [Net.Http.HttpResponseMessage]::new() }
			Mock GetDigest { 'sha256:00000000000000000000' }
			Mock GetSize {}
			Mock WriteHost {}
			Mock InstallPackage { @{}, 'new' }
			Mock SavePackage {
				$pkgPath = (@{} | ResolveRemoteRef |GetManifest | GetDigest) | ResolvePackagePath
				MakeDirIfNotExist $pkgPath | Out-Null
				Set-Content -Path "$pkgPath\file.txt" -Value 'abc123'
			}
			Mock GetAirpowerPath {
				$testPath
			}
		}
		AfterEach {
			[IO.Directory]::Delete("$testPath\ref\somepkg")
			[IO.Directory]::Delete($testPath, $true)
		}
		It 'No Exist Creates New' {
			$pkg = @{
				Package = 'somepkg'
				Tag = @{ Latest = $true }
			}
			$pkg | PullPackage
			$want = (Get-FileHash "$testPath\content\000000000000\file.txt").Hash
			$got = (Get-FileHash "$testPath\ref\somepkg\file.txt").Hash
			$got | Should -Be $want
		}
		It 'Exist Creates New' {
			New-Item "$testPath\ref" -ItemType Directory
			New-Item "$testPath\content\xxx" -ItemType Directory
			Set-Content -Path "$testPath\content\xxx\file.txt" -Value 'something'
			New-Item "$testPath\ref\somepkg" -ItemType Junction -Target "$testPath\content\xxx"
			$pkg = @{
				Package = 'somepkg'
				Tag = @{ Latest = $true }
			}
			$pkg | PullPackage
			$want = (Get-FileHash "$testPath\content\000000000000\file.txt").Hash
			$got = (Get-FileHash "$testPath\ref\somepkg\file.txt").Hash
			$got | Should -Be $want
		}
	}
}

Describe 'RemovePackage' {
	Context 'Ref' {
		$script:testRoot = (Resolve-Path "$PSScriptRoot\..\test").Path
		$script:testPath = "$testRoot\remove_package_test"
		BeforeAll {
			Mock ResolveRemoteRef { 'none' }
			Mock OutPwrDB {}
			Mock WriteHost {}
			Mock UninstallPackage { @{}, 'sha256:00000000000000000000', $null }
			Mock GetAirpowerPath {
				$testPath
			}
		}
		AfterEach {
			if (Test-Path -Path "$testPath\ref\somepkg" -PathType Container) {
				[IO.Directory]::Delete("$testPath\ref\somepkg")
			}
			if (Test-Path -Path $testPath -PathType Container) {
				[IO.Directory]::Delete($testPath, $true)
			}
		}
		It 'Exist Deletes' {
			New-Item "$testPath\ref" -ItemType Directory
			New-Item "$testPath\content\xxx" -ItemType Directory
			Set-Content -Path "$testPath\content\xxx\file.txt" -Value 'something'
			New-Item "$testPath\ref\somepkg" -ItemType Junction -Target "$testPath\content\xxx"
			$pkg = @{
				Package = 'somepkg'
				Tag = @{ Latest = $true }
			}
			$pkg | RemovePackage
			Test-Path -Path "$testPath\ref\somepkg" -PathType Container | Should -Be $false
		}
		It 'No Exist No Throw' {
			$pkg = @{
				Package = 'somepkg'
				Tag = @{ Latest = $true }
			}
			{ $pkg | RemovePackage } | Should -Not -Throw
		}
	}
}