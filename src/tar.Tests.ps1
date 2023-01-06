BeforeAll {
	. $PSCommandPath.Replace('.Tests.ps1','.ps1')
}

$script:root = Resolve-Path "$PSScriptRoot\..\test"
$script:tgz = "$root\70f0de6b501a64372ea26d2c12d2eead94f77391bd040c96f2d8b92ffd53fdbe.tar.gz"

Describe "Untargz" {
	BeforeAll {
		$script:PwrHome = "$root\airpower"
		Mock ResolvePackagePath {
			return "$PwrHome\0123456789abc"
		}
		Mock WriteConsole {}
		Mock WritePeriodicConsole {}
	}
	AfterAll {
		[IO.Directory]::Delete($PwrHome, $true)
		[IO.File]::Delete($tgz.Replace('.tar.gz', '.tar'))
	}
	It "Extracts" {
		$tar = $tgz | DecompressTarGz
		$tar | ExtractTar -Digest '1234567890ab'
		Get-Content "$(ResolvePackagePath '_')\file.txt" -Raw | Should -Be 'A'
		Get-ChildItem -File -Recurse -Path "$(ResolvePackagePath '_')\nested" |
			Select-Object -First 1 |
			Get-Content -Raw |
			Should -Be 'XYZ'
	}
}