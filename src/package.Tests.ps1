BeforeAll {
	. $PSCommandPath.Replace('.Tests.ps1','.ps1')
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
					}
					'metadatadb' = @{
						'abc' = @{RefCount = 1}
						'xyz' = @{RefCount = 1}
						'fde54e65gd4678' = @{RefCount = 0; Size = 3}
						'e340857fffc987' = @{RefCount = 0; Size = 5}
					}
				}
			}
		}
		It 'Prunes' {
			$db, $pruned = UninstallOrhpanedPackages
			$pruned.Count | Should -Be 2
			$db.pkgdb.somepkg.Count | Should -Be 1
			$db.pkgdb.somepkg.latest | Should -Be 'abc'
			$db.pkgdb.another.Count | Should -Be 1
			$db.pkgdb.another.latest | Should -Be 'xyz'
			$db.metadatadb.count | Should -Be 2
			$db.metadatadb.fde54e65gd4678 | Should -Be $null
			$db.metadatadb.e340857fffc987 | Should -Be $null
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
			$db, $pruned = UninstallOrhpanedPackages
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