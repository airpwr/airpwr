BeforeAll {
	. $PSCommandPath.Replace('.Tests.ps1', '.ps1')
}

Describe 'FindConfig' {
	BeforeAll {
		$script:AirpowerPath = "$root\airpower"
		Mock Get-Location {
			@{Path = 'C:\a\b\c\d'}
		}
	}
	It 'Local config' {
		Mock Test-Path {
			return $true
		}
		$cfg = FindConfig
		$cfg | Should -Be 'C:\a\b\c\d\Airpower.ps1'
	}
	It 'Parent config' {
		$script:i = 0
		Mock Test-Path {
			return ($script:i++) -gt 0
		}
		$cfg = FindConfig
		$cfg | Should -Be 'C:\a\b\c\Airpower.ps1'
	}
	It 'No config' {
		Mock Test-Path {
			return $false
		}
		$cfg = FindConfig
		$cfg | Should -Be $null
	}
}
