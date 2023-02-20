BeforeAll {
	. $PSCommandPath.Replace('.Tests.ps1', '.ps1')
	$script:root = (Resolve-Path "$PSScriptRoot\..\test").Path
}

Describe "Db" {
	BeforeAll {
		$script:AirpowerPath = "$root\airpower"
	}
	BeforeEach {
		[Db]::Init()
	}
	AfterEach {
		[IO.Directory]::Delete("\\?\$AirpowerPath", $true)
	}
	It "Get No Exist" {
		$v, $err = [Db]::TryGet("no such")
		$v | Should -Be $null
	}
	It "Get Empty" {
		[Db]::Put("x", '')
		$v, $err = [Db]::TryGet('x')
		$v | Should -Be ''
	}
	It "Get Null" {
		[Db]::Put("x", $null)
		$v, $err = [Db]::TryGet('x')
		$v | Should -Be $null
	}
	It "Put and Get" {
		$k = "a", "b"
		$v = "some value"
		[Db]::Put($k, $v)
		[Db]::Get($k) | Should -Be $v
	}
	It "GetAll" {
		[Db]::Put("xyz", 0)
		[Db]::Put(("x", 1), 5)
		[Db]::Put(("x", 1, 1), 6)
		[Db]::Put(("x", 2), 7)
		[Db]::GetAll("x").Value | Should -Be 5, 6, 7
	}
	It "Read x2" {
		$k = "x"
		$lock1, $err = [Db]::TryRLock($k)
		$err | Should -BeNullOrEmpty
		$lock2, $err = [Db]::TryRLock($k)
		$err | Should -BeNullOrEmpty
		if ($lock1) {
			$lock1.Unlock()
		}
		if ($lock2) {
			$lock2.Unlock()
		}
	}
	It "Read & Write" {
		$k = "x"
		$lock1, $err = [Db]::TryRLock($k)
		$err | Should -BeNullOrEmpty
		$lock2, $err = [Db]::TryLock($k)
		$err | Should -Not -BeNullOrEmpty
		if ($lock1) {
			$lock1.Unlock()
		}
		if ($lock2) {
			$lock2.Unlock()
		}
	}
	It "Write x2" {
		$k = "x"
		$lock1, $err = [Db]::TryLock($k)
		$err | Should -BeNullOrEmpty
		$lock2, $err = [Db]::TryLock($k)
		$err | Should -Not -BeNullOrEmpty
		if ($lock1) {
			$lock1.Unlock()
		}
		if ($lock2) {
			$lock2.Unlock()
		}
	}
}
