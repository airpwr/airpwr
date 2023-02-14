BeforeAll {
	. $PSCommandPath.Replace('.Tests.ps1', '.ps1')
}

$script:root = (Resolve-Path "$PSScriptRoot\..\test").Path
$script:tgz = "$root\70f0de6b501a64372ea26d2c12d2eead94f77391bd040c96f2d8b92ffd53fdbe.tar.gz"
$script:tgz = "$root\e28d6af1b2dbcc7169b25f1316cf867b0de580d15c0610ccf8d10feb421e7d49.tar.gz"


Describe "Untargz" {
	BeforeAll {
		$script:AirpowerPath = "$root\airpower"
		Mock ResolvePackagePath {
			return "$AirpowerPath\0123456789abc"
		}
		Mock WriteConsole {}
		Mock WritePeriodicConsole {}
	}
	AfterAll {
		[IO.Directory]::Delete("\\?\$AirpowerPath", $true)
	}
	It "Extracts" {
		$tgz | ExtractTarGz -Digest '1234567890ab'
		$pkg = ResolvePackagePath '_'
		Get-Content "$pkg\file.txt" -Raw | Should -Be 'A'
		Get-Content "$pkg\empty.txt" -Raw | Should -Be ''
		[IO.File]::ReadAllText("\\?\$pkg\nested\Some-Really-Long-Folder-Name----------------------------------------------------------------------------------------------------\Some-Really-Long-Folder-Name-----------------------------------------------------\a.txt") | Should -Be 'xyz'
	}
}
