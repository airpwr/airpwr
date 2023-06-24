BeforeAll {
	. $PSCommandPath.Replace('.Tests.ps1', '.ps1')
}

Describe "GetAuthToken" {
	BeforeAll {
		Mock HttpSend {
			param (
				[Net.Http.HttpRequestMessage]$Req
			)
			$Req.RequestUri.OriginalString | Should -Match (GetDockerRepo)
			if ($Req.RequestUri.OriginalString.Contains('auth.docker.io')) {
				$content = @{
					Token = 'abc123'
				}
			} else {
				throw "unexpected uri: $($Req.RequestUri)"
			}
			$resp = [Net.Http.HttpResponseMessage]::new()
			$resp.Content = [Net.Http.StringContent]::new((ConvertTo-Json $content))
			$resp.Content.Headers.ContentType.MediaType = 'application/json'
			return $resp
		}
	}
	It "Response Token" {
		GetAuthToken | Should -Be 'abc123'
	}
}

Describe "GetTagsList" {
	BeforeAll {
		Mock GetAuthToken {
			return 'token'
		}
		Mock HttpSend {
			param (
				[Net.Http.HttpRequestMessage]$Req
			)
			$Req.RequestUri.OriginalString | Should -Match (GetDockerRepo)
			if ($Req.RequestUri.OriginalString.Contains('index.docker.io')) {
				$content = @{
					Name = 'Name'
					Tags = @('Tag1', 'Tag2')
				}
			} else {
				throw "unexpected uri: $($Req.RequestUri)"
			}
			$resp = [Net.Http.HttpResponseMessage]::new()
			$resp.Content = [Net.Http.StringContent]::new((ConvertTo-Json $content))
			$resp.Content.Headers.ContentType.MediaType = 'application/json'
			return $resp
		}
	}
	It "Tags Match" {
		$tags = GetTagsList
		$tags.Tags | Should -Be @('Tag1', 'Tag2')
	}
}
