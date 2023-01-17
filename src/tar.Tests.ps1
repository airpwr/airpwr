BeforeAll {
	. $PSCommandPath.Replace('.Tests.ps1', '.ps1')
}

$script:root = (Resolve-Path "$PSScriptRoot\..\test").Path
$script:tgz = "$root\70f0de6b501a64372ea26d2c12d2eead94f77391bd040c96f2d8b92ffd53fdbe.tar.gz"

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
		[IO.File]::ReadAllText("\\?\$pkg\nested\Some-Really-Long-Folder-Name----------------------------------------------------------------------------------------------------\Some-Really-Long-Folder-Name-----------------------------------------------------\a.txt") | Should -Be 'xyz'
	}
}
