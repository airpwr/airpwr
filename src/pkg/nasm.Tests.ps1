BeforeAll {
	. $PSScriptRoot\..\pwr.ps1
	$pwr = "$PSScriptRoot\..\..\pwr"
	[IO.Directory]::CreateDirectory($pwr)
	$script:AirpowerPath = (Resolve-Path $pwr).Path
}

AfterAll {
	[IO.Directory]::Delete($script:AirpowerPath, $true)
}

Describe 'nasm' {
	It 'all' {
		$tags, $digests = AirpowerPackageNasm
		$tags | Should -Not -BeNullOrEmpty -ErrorAction Stop
		$digests | Should -Not -BeNullOrEmpty -ErrorAction Stop
	}
	It 'latest' {
		$tag, $digest = AirpowerPackageNasm 'latest'
		$tag | Should -Not -BeNullOrEmpty -ErrorAction Stop
		$digest | Should -Not -BeNullOrEmpty -ErrorAction Stop
		$size = AirpowerPackageNasm -TagName $tag -Digest $digest
		$size | Should -BeGreaterThan 0
		' ' * 90 + "`n" | WriteConsole
	}
	It 'exec' {
		Invoke-AirpowerExec -Packages 'nasm' -ScriptBlock {
			nasm --version
		}
		Invoke-AirpowerRemove -Packages 'nasm'
	}
}