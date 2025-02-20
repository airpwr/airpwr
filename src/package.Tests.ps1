BeforeAll {
	. $PSCommandPath.Replace('.Tests.ps1', '.ps1')
	Mock WriteHost {}
	$script:root = (Resolve-Path "$PSScriptRoot\..\test").Path
	$script:AirpowerPath = "$root\airpower"
}

Describe 'TryEachPackage' {
	Context 'Invoked with a test function that throws if not a or b' {
		BeforeAll {
			Mock AsPackage {
				param (
					[Parameter(Mandatory, ValueFromPipeline)]
					[string]$Pkg
				)
				if (-not ('a', 'b' -contains $Pkg)) {
					throw "[Test] Package is not valid: $Pkg"
				}
				return $Pkg
			}
		}
		It 'Does not throw for packages a and b' {
			TryEachPackage 'a', 'b' { $Input | AsPackage } | Should -Be 'a', 'b'
		}
		It 'Throws for packages c and d, but still tries a and b' {
			{ TryEachPackage 'c', 'b', 'a', 'd' { $Input | AsPackage } -ActionDescription 'test' } | Should -Throw
			Should -Invoke -CommandName 'AsPackage' -Exactly -Times 4
		}
	}
}

Describe 'InstallPackage' {
	BeforeEach {
		[Db]::Init()
	}
	AfterEach {
		[IO.Directory]::Delete("\\?\$root\airpower", $true)
	}
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
			$locks, $status = $pkg | InstallPackage
			try {
				$status | Should -Be 'new'
			} finally {
				$locks.Unlock()
			}
			[Db]::Get(('pkgdb', 'somepkg', 'latest')) | Should -Be 'fde54e65gd4678'
			[Db]::Get(('metadatadb', 'fde54e65gd4678')).refcount | Should -Be 1
			[Db]::Get(('metadatadb', 'fde54e65gd4678')).size | Should -Be 982365234
		}
	}
	Context 'New Tag, Same Digest' {
		BeforeEach {
			[Db]::Put(('pkgdb', 'somepkg', 'latest'), 'fde54e65gd4678')
			[Db]::Put(('metadatadb', 'fde54e65gd4678'), @{
				RefCount = 1
				Size = 293874
			})
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
			$locks, $status = $pkg | InstallPackage
			try {
				$status | Should -Be 'tag'
			} finally {
				$locks.Unlock()
			}
			[Db]::Get(('pkgdb', 'somepkg', 'latest')) | Should -Be 'fde54e65gd4678'
			[Db]::Get(('pkgdb', 'somepkg', '1.2')) | Should -Be 'fde54e65gd4678'
			[Db]::Get(('metadatadb', 'fde54e65gd4678')).refcount | Should -Be 2
			[Db]::Get(('metadatadb', 'fde54e65gd4678')).size | Should -Be 293874
		}
	}
	Context 'Same Tag, New Digest' {
		BeforeEach {
			[Db]::Put(('pkgdb', 'somepkg', 'latest'), 'fde54e65gd4678')
			[Db]::Put(('metadatadb', 'fde54e65gd4678'), @{
				RefCount = 1
				Size = 293874
			})
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
			$locks, $status = $pkg | InstallPackage
			try {
				$status | Should -Be 'newer'
			} finally {
				$locks.Unlock()
			}
			[Db]::Get(('pkgdb', 'somepkg', 'latest')) | Should -Be 'abc123'
			[Db]::ContainsKey(('pkgdb', 'somepkg', 'fde54e65gd4678')) | Should -Be $true
			[Db]::Get(('pkgdb', 'somepkg', 'fde54e65gd4678')) | Should -Be $null
			[Db]::Get(('metadatadb', 'fde54e65gd4678')).refcount | Should -Be 0
			[Db]::Get(('metadatadb', 'fde54e65gd4678')).orphaned | Should -Not -BeNullOrEmpty
			[Db]::Get(('metadatadb', 'fde54e65gd4678')).size | Should -Be 293874
			[Db]::Get(('metadatadb', 'abc123')).refcount | Should -Be 1
			[Db]::Get(('metadatadb', 'abc123')).size | Should -Be 999123
		}
	}
	Context 'Same Tag, New Digest, Multi Ref' {
		BeforeEach {
			[Db]::Put(('pkgdb', 'somepkg', 'latest'), 'fde54e65gd4678')
			[Db]::Put(('pkgdb', 'somepkg', '1.2'), 'fde54e65gd4678')
			[Db]::Put(('metadatadb', 'fde54e65gd4678'), @{
				RefCount = 2
				Size = 293874
			})
		}
		It 'Replaces and Decrements' {
			$pkg = @{
				Package = 'somepkg'
				Tag = @{
					Latest = $true
				}
				Digest = 'abc123'
				Size = 999123
			}
			$locks, $status = $pkg | InstallPackage
			try {
				$status | Should -Be 'newer'
			} finally {
				$locks.Unlock()
			}
			[Db]::Get(('pkgdb', 'somepkg', 'latest')) | Should -Be 'abc123'
			[Db]::ContainsKey(('pkgdb', 'somepkg', 'fde54e65gd4678')) | Should -Be $false
			[Db]::Get(('metadatadb', 'fde54e65gd4678')).refcount | Should -Be 1
			[Db]::Get(('metadatadb', 'fde54e65gd4678')).size | Should -Be 293874
			[Db]::Get(('metadatadb', 'abc123')).refcount | Should -Be 1
			[Db]::Get(('metadatadb', 'abc123')).size | Should -Be 999123
		}
	}
	Context 'From RefCount 0' {
		BeforeEach {
			[Db]::Put(('pkgdb', 'somepkg', 'fde54e65gd4678'), $null)
			[Db]::Put(('metadatadb', 'fde54e65gd4678'), @{
				RefCount = 0
				Size = 293874
				Orphaned = [DateTime]::UtcNow.ToString('u')
			})
		}
		It 'Installs' {
			$pkg = @{
				Package = 'somepkg'
				Tag = @{
					Latest = $true
				}
				Digest = 'fde54e65gd4678'
			}
			$locks, $status = $pkg | InstallPackage
			try {
				$status | Should -Be 'tag'
			} finally {
				$locks.Unlock()
			}
			[Db]::Get(('pkgdb', 'somepkg', 'latest')) | Should -Be 'fde54e65gd4678'
			[Db]::ContainsKey(('pkgdb', 'somepkg', 'fde54e65gd4678')) | Should -Be $false
			[Db]::Get(('metadatadb', 'fde54e65gd4678')).refcount | Should -Be 1
			[Db]::Get(('metadatadb', 'fde54e65gd4678')).size | Should -Be 293874
			[Db]::Get(('metadatadb', 'fde54e65gd4678')).orphaned | Should -Be $null
		}
	}
	Context 'From Specific Tag' {
		BeforeEach {
			[Db]::Put(('pkgdb', 'somepkg', 'latest'), '6523af3e765545')
			[Db]::Put(('pkgdb', 'somepkg', '1.2.3'), 'fde54e65gd4678')
			[Db]::Put(('metadatadb', 'fde54e65gd4678'), @{
				RefCount = 1
				Size = 293874
			})
			[Db]::Put(('metadatadb', '6523af3e765545'), @{
				RefCount = 1
				Size = 293874
			})
		}
		It 'Tags Latest' {
			$pkg = @{
				Package = 'somepkg'
				Tag = @{
					Latest = $true
				}
				Digest = 'fde54e65gd4678'
			}
			$locks, $status = $pkg | InstallPackage
			try {
				$status | Should -Be 'ref'
			} finally {
				$locks.Unlock()
			}
			[Db]::Get(('pkgdb', 'somepkg', 'latest')) | Should -Be 'fde54e65gd4678'
			[Db]::Get(('pkgdb', 'somepkg', '1.2.3')) | Should -Be 'fde54e65gd4678'
			[Db]::Get(('metadatadb', 'fde54e65gd4678')).refcount | Should -Be 2
			[Db]::Get(('metadatadb', 'fde54e65gd4678')).size | Should -Be 293874
			[Db]::Get(('metadatadb', '6523af3e765545')).refcount | Should -Be 0
		}
	}
}

Describe 'UninstallPackage' {
	BeforeEach {
		[Db]::Init()
	}
	AfterEach {
		[IO.Directory]::Delete("\\?\$root\airpower", $true)
	}
	Context 'From 2+' {
		BeforeEach {
			[Db]::Put(('pkgdb', 'somepkg', 'latest'), 'fde54e65gd4678')
			[Db]::Put(('pkgdb', 'somepkg', '1.2'), 'fde54e65gd4678')
			[Db]::Put(('metadatadb', 'fde54e65gd4678'), @{
				RefCount = 2
				Size = 293874
			})
		}
		It 'Decrements' {
			$pkg = @{
				Package = 'somepkg'
				Tag = @{
					Major = 1
					Minor = 2
				}
			}
			$locks, $digest, $null = $pkg | UninstallPackage
			$locks.Unlock()
			$digest | Should -Be $null
			[Db]::Get(('pkgdb', 'somepkg', 'latest')) | Should -Be 'fde54e65gd4678'
			[Db]::ContainsKey(('pkgdb', 'somepkg', '1.2')) | Should -Be $false
			[Db]::Get(('metadatadb', 'fde54e65gd4678')).refcount | Should -Be 1
		}
	}
	Context 'From 1' {
		BeforeEach {
			[Db]::Put(('pkgdb', 'somepkg', 'latest'), 'fde54e65gd4678')
			[Db]::Put(('metadatadb', 'fde54e65gd4678'), @{
				RefCount = 1
				Size = 293874
			})
		}
		It 'Removes' {
			$pkg = @{
				Package = 'somepkg'
				Tag = @{
					Latest = $true
				}
			}
			$locks, $digest, $null = $pkg | UninstallPackage
			$locks.Unlock()
			$digest | Should -Not -Be $null
			[Db]::ContainsKey(('pkgdb', 'somepkg', 'latest')) | Should -Be $false
			[Db]::ContainsKey(('metadatadb', 'fde54e65gd4678')) | Should -Be $false
		}
	}
}

Describe 'PrunePackages' {
	BeforeEach {
		[Db]::Init()
	}
	AfterEach {
		[IO.Directory]::Delete("\\?\$root\airpower", $true)
	}
	Context 'From DB' {
		BeforeEach {
			[Db]::Put(('pkgdb', 'somepkg', 'sha256:fde54e65gd4678'), $null)
			[Db]::Put(('pkgdb', 'somepkg', 'latest'), 'abc')
			[Db]::Put(('pkgdb', 'another', 'sha256:e340857fffc987'), $null)
			[Db]::Put(('pkgdb', 'another', 'latest'), 'xyz')
			[Db]::Put(('metadatadb', 'abc'), @{RefCount = 1})
			[Db]::Put(('metadatadb', 'xyz'), @{RefCount = 1})
			[Db]::Put(('metadatadb', 'sha256:fde54e65gd4678'), @{RefCount = 0; Size = 3; Orphaned = '0001-01-01 00:00:00Z'})
			[Db]::Put(('metadatadb', 'sha256:e340857fffc987'), @{RefCount = 0; Size = 5; Orphaned = '2999-01-01 00:00:00Z'})
		}
		It 'Prunes' {
			$locks, $metadata = UninstallOrphanedPackages
			$locks.Unlock()
			$metadata.Count | Should -Be 2
			[Db]::Get(('pkgdb', 'somepkg', 'latest')) | Should -Be 'abc'
			[Db]::Get(('pkgdb', 'another', 'latest')) | Should -Be 'xyz'
			[Db]::ContainsKey(('pkgdb', 'somepkg', 'sha256:fde54e65gd4678')) | Should -Be $false
			[Db]::ContainsKey(('pkgdb', 'another', 'sha256:e340857fffc987')) | Should -Be $false
			[Db]::ContainsKey(('metadatadb', 'sha256:fde54e65gd4678')) | Should -Be $false
			[Db]::ContainsKey(('metadatadb', 'sha256:e340857fffc987')) | Should -Be $false
		}
		It 'Prunes by timespan' {
			$locks, $metadata = UninstallOrphanedPackages ([timespan]::new(1, 1, 1))
			$locks.Unlock()
			$metadata.Count | Should -Be 1
			[Db]::Get(('pkgdb', 'somepkg', 'latest')) | Should -Be 'abc'
			[Db]::Get(('pkgdb', 'another', 'latest')) | Should -Be 'xyz'
			[Db]::ContainsKey(('pkgdb', 'somepkg', 'sha256:fde54e65gd4678')) | Should -Be $false
			[Db]::ContainsKey(('pkgdb', 'another', 'sha256:e340857fffc987')) | Should -Be $true
			[Db]::ContainsKey(('metadatadb', 'sha256:fde54e65gd4678')) | Should -Be $false
			[Db]::ContainsKey(('metadatadb', 'sha256:e340857fffc987')) | Should -Be $true
		}
	}
	Context 'Auto' {
		BeforeAll {
			Mock UninstallOrphanedPackages { @(), @() }
			$script:AirpowerAutoprune = "4.11:22:33"
		}
		AfterAll {
			$script:AirpowerAutoprune = $null
		}
		It 'Prunes' {
			PrunePackages -Auto
			Should -Invoke -CommandName 'UninstallOrphanedPackages' -Exactly -Times 1 -ParameterFilter { $Span -eq [timespan]::new(4, 11, 22, 33) }
		}
	}
}

Describe 'UpdatePackages' {
	BeforeEach {
		[Db]::Init()
	}
	AfterEach {
		[IO.Directory]::Delete("\\?\$root\airpower", $true)
	}
	Context 'From DB' {
		BeforeEach {
			[Db]::Put(('pkgdb', 'somepkg', 'sha256:fde54e65gd4678'), $null)
			[Db]::Put(('pkgdb', 'somepkg', 'latest'), 'abc')
			[Db]::Put(('pkgdb', 'another', 'sha256:e340857fffc987'), $null)
			[Db]::Put(('pkgdb', 'another', 'latest'), 'xyz')
			[Db]::Put(('metadatadb', 'abc'), @{RefCount = 1; Updated = '0001-01-01 00:00:00Z'})
			[Db]::Put(('metadatadb', 'xyz'), @{RefCount = 1; Updated = '2999-01-01 00:00:00Z'})
			[Db]::Put(('metadatadb', 'sha256:fde54e65gd4678'), @{RefCount = 1; Updated = '0001-01-01 00:00:00Z'})
			[Db]::Put(('metadatadb', 'sha256:e340857fffc987'), @{RefCount = 1; Updated = '2999-01-01 00:00:00Z'})
		}
		It 'Updates' {
			Mock PullPackage {
				return 'newer'
			}
			UpdatePackages
			Should -Invoke -CommandName 'PullPackage' -Exactly -Times 2
		}
		It 'Outofdate' {
			$pkgs = GetOutofdatePackages ([timespan]::MinValue)
			$pkgs.Count | Should -Be 2
			$pkgs | Should -Contain 'somepkg:latest'
			$pkgs | Should -Contain 'another:latest'
		}
		It 'Outofdate by timespan' {
			$pkgs = GetOutofdatePackages ([timespan]::Zero)
			$pkgs.Count | Should -Be 1
			$pkgs | Should -Be 'somepkg:latest'
		}
	}
	Context 'Auto' {
		BeforeAll {
			$script:AirpowerAutoupdate = "4.11:22:33"
		}
		BeforeEach {
			[Db]::Put(('pkgdb', 'somepkg', 'sha256:fde54e65gd4678'), $null)
			[Db]::Put(('pkgdb', 'somepkg', 'latest'), 'abc')
			[Db]::Put(('pkgdb', 'another', 'sha256:e340857fffc987'), $null)
			[Db]::Put(('pkgdb', 'another', 'latest'), 'xyz')
			[Db]::Put(('metadatadb', 'abc'), @{RefCount = 1; Updated = '0001-01-01 00:00:00Z'})
			[Db]::Put(('metadatadb', 'xyz'), @{RefCount = 1; Updated = '0001-01-01 00:00:00Z'})
			[Db]::Put(('metadatadb', 'sha256:fde54e65gd4678'), @{RefCount = 1; Updated = '0001-01-01 00:00:00Z'})
			[Db]::Put(('metadatadb', 'sha256:e340857fffc987'), @{RefCount = 1; Updated = '0001-01-01 00:00:00Z'})
		}
		AfterAll {
			$script:AirpowerAutoupdate = $null
		}
		It 'Outofdate' {
			Mock GetOutofdatePackages { @() }
			UpdatePackages -Auto
			Should -Invoke -CommandName 'GetOutofdatePackages' -Exactly -Times 1 -ParameterFilter { $Span -eq [timespan]::new(4, 11, 22, 33) }
		}
		It 'Updates' {
			Mock PullPackage {
				return 'newer'
			}
			UpdatePackages -Auto somepkg
			Should -Invoke -CommandName 'PullPackage' -Exactly -Times 1
		}
	}
}

Describe 'ResolvePackageDigest' {
	BeforeEach {
		[Db]::Init()
	}
	AfterEach {
		[IO.Directory]::Delete("\\?\$root\airpower", $true)
	}
	Context 'From DB' {
		BeforeEach {
			[Db]::Put(('pkgdb', 'somepkg', '1.2'), 'sha256:fde54e65gd4678')
			[Db]::Put(('metadatadb', 'sha256:fde54e65gd4678'), @{RefCount = 1; Size = 3})
		}
		It 'Resolves' {
			$pkg = @{
				Package = 'somepkg'
				Tag = @{
					Major = 1
					Minor = 2
				}
			}
			$d = $pkg | ResolvePackageDigest
			$d | Should -Be 'sha256:fde54e65gd4678'
		}
	}
}

Describe 'GetLocalPackages' {
	BeforeEach {
		[Db]::Init()
	}
	AfterEach {
		[IO.Directory]::Delete("\\?\$root\airpower", $true)
	}
	Context 'From Nothing' {
		It 'Blank' {
			$pkgs = GetLocalPackages
			$pkgs | Should -HaveCount 1
			$pkgs[0].Package | Should -Be $null
			$pkgs[0].Tag | Should -Be $null
			$pkgs[0].Digest | Should -Be $null
			$pkgs[0].Version | Should -Be $null
			$pkgs[0].Size | Should -Be $null
		}
	}
	Context 'From DB' {
		BeforeEach {
			$digest = 'sha256:41d9d6d55caf3de74832ac7d7f4226180b305e1d76f00f72dde2581e7f1e4b94'
			[Db]::Put(('pkgdb', 'somepkg', 'latest'), $digest)
			[Db]::Put(('metadatadb', $digest), @{
				RefCount = 1
				Version = "1"
				Size = 293874
			})
		}
		It 'Shows' {
			$pkgs = GetLocalPackages
			$pkgs | Should -HaveCount 1
			$pkgs[0].Package | Should -Be 'somepkg'
			$pkgs[0].Tag | Should -Be 'latest'
			$pkgs[0].Digest.Sha256 | Should -Be $digest
			$pkgs[0].Version | Should -Be "1"
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

			Mock GetManifest { [Net.Http.HttpResponseMessage]::new() }
			Mock GetDigest { 'sha256:00000000000000000000' }
			Mock DebugRateLimit {}
			Mock GetSize {}
			Mock WriteHost {}
			Mock InstallPackage { @(New-MockObject -Type 'System.Object' -Methods @{Unlock = {}; Revert = {}}), 'new' }
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
	Context 'DB Contains Key' {
		BeforeAll {
			New-Item -ItemType Directory -Path "$root\airpower\cache" -ErrorAction Ignore | Out-Null
			Mock ResolveRemoteRef { 'none' }
			Mock GetDigestForRef { 'f12345' }
			Mock WriteHost {}
			Mock InstallPackage { @(New-MockObject -Type 'System.Object' -Methods @{Unlock = {}; Revert = {}}), 'ref' }
			Mock MakeDirIfNotExist {}
			Mock SavePackage {}
			Mock ResolvePackagePath {}
			Mock New-Item {}
		}
		AfterAll {
			[IO.Directory]::Delete("$root\airpower", $true)
		}
		It 'Does not SavePackage' {
			$pkg = @{
				Package = 'somepkg'
				Tag = @{ Latest = $true }
			}
			$pkg | PullPackage
			Should -Invoke -CommandName 'SavePackage' -Exactly -Times 0
		}
	}
}

Describe 'RemovePackage' {
	Context 'Ref' {
		$script:testRoot = (Resolve-Path "$PSScriptRoot\..\test").Path
		$script:testPath = "$testRoot\remove_package_test"
		BeforeAll {
			Mock ResolveRemoteRef { 'none' }
			Mock WriteHost {}
			Mock UninstallPackage { @(New-MockObject -Type 'System.Object' -Methods @{Unlock = {}; Revert = {}}), 'sha256:00000000000000000000', $null }
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

Describe 'SavePackage' {
	Context 'Ref' {
		$script:testRoot = (Resolve-Path "$PSScriptRoot\..\test").Path
		$script:testPath = "$testRoot\save_package_test"
		BeforeAll {
			Mock ResolveRemoteRef { 'none' }

			Mock GetManifest {
				$response = [Net.Http.HttpResponseMessage]::new([Net.HttpStatusCode]::OK)
				$response.Headers.Add('Docker-Content-Digest', "sha256:00000000000000000000")
				$response.Content = [Net.Http.StringContent]::new('none manifest')
				return $response
			}
			Mock DebugRateLimit {}
			Mock GetSize {}
			Mock WriteHost {}
			Mock SavePackage {
				param (
					[Parameter(Mandatory, ValueFromPipeline)]
					[Net.Http.HttpResponseMessage]$Resp,
					[String]$Output
				)
				$null = $Resp
				MakeDirIfNotExist $Output | Out-Null
				Set-Content -Path "$Output\file.txt" -Value 'abc123'
			}
			Mock GetAirpowerPath {
				$testPath
			}
		}
		AfterEach {
			[IO.Directory]::Delete($testPath, $true)
		}
		It 'No Exist Creates New' {
			$pkg = @{
				Package = 'somepkg'
				Tag = @{ Latest = $true }
			}
			$pkg | PullPackage -Output "$testPath\cache"
			"$testPath\cache\none\manifest.json" | Should -Exist
			"$testPath\cache\none\manifest.json" | Should -FileContentMatchExactly 'none manifest'
			"$testPath\cache\none\file.txt" | Should -Exist
			"$testPath\cache\none\file.txt" | Should -FileContentMatchExactly 'abc123'
		}
		It 'Exist Creates New' {
			New-Item "$testPath\cache" -ItemType Directory
			New-Item "$testPath\cache\none" -ItemType Directory
			Set-Content -Path "$testPath\cache\none\manifest.json" -Value 'something'
			Set-Content -Path "$testPath\cache\none\file.txt" -Value 'something'
			$pkg = @{
				Package = 'somepkg'
				Tag = @{ Latest = $true }
			}
			$pkg | PullPackage -Output "$testPath\cache"
			"$testPath\cache\none\manifest.json" | Should -Exist
			"$testPath\cache\none\manifest.json" | Should -FileContentMatchExactly 'none manifest'
			"$testPath\cache\none\file.txt" | Should -Exist
			"$testPath\cache\none\file.txt" | Should -FileContentMatchExactly 'abc123'
		}
	}
}
