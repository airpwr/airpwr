BeforeAll {
	. $PSCommandPath.Replace('.Tests.ps1', '.ps1')
}

Describe "HttpSend" {
	It "200 OK" {
		$resp = HttpRequest 'http://github.com' | HttpSend
		$resp | Should -Not -BeNullOrEmpty -ErrorAction Stop
		$resp.IsSuccessStatusCode | Should -Be $true
	}
}

Describe "GetJsonResponse" {
	It "JSON Content" {
		$resp = [Net.Http.HttpResponseMessage]::new()
		$resp.Content = [Net.Http.StringContent]::new('{"A": "B"}')
		$resp.Content.Headers.ContentType.MediaType = 'application/json'

		$content = GetJsonResponse -Resp $resp
		$content.A | Should -Be 'B'
	}
	It "Throw Other Content" {
		$resp = [Net.Http.HttpResponseMessage]::new()
		$resp.Content = [Net.Http.StringContent]::new('any')

		{ GetJsonResponse -Resp $resp } | Should -Throw
	}
}


