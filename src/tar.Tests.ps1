BeforeAll {
	. $PSCommandPath.Replace('.Tests.ps1', '.ps1')
}

$script:root = (Resolve-Path "$PSScriptRoot\..\test").Path
$script:tgz = "$root\a9258b98bfc2c8ed0af1a6e7ee55e604286820c7bf81768ed0da34d5ed87d483.tar.gz"

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
		Get-Content "$pkg\empty.txt" -Raw | Should -Be $null
		[IO.File]::ReadAllText("\\?\$pkg\nested\Some-Really-Long-Folder-Name----------------------------------------------------------------------------------------------------\Some-Really-Long-Folder-Name-----------------------------------------------------\a.txt") | Should -Be 'xyz'
	}
}
