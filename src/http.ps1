Add-Type -AssemblyName System.Net.Http

function HttpRequest {
	param (
		[Parameter(Mandatory)]
		[string]$URL,
		[ValidateSet('GET', 'HEAD')]
		[string]$Method = 'GET',
		[string]$AuthToken,
		[string]$Accept,
		[string]$Range
	)
	$req = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::new($Method), $URL)
	if ($AuthToken) {
		$req.Headers.Authorization = "Bearer $AuthToken"
	}
	if ($Accept) {
		$req.Headers.Accept.Add($Accept)
	}
	if ($Range) {
		$req.Headers.Range = $Range
	}
	return $req
}

function HttpSend {
	param(
		[Parameter(Mandatory, ValueFromPipeline)]
		[Net.Http.HttpRequestMessage]$Req,
		[switch]$NoRedirect
	)
	$ch = [Net.Http.HttpClientHandler]::new()
	if ($NoRedirect) {
		$ch.AllowAutoRedirect = $false
	}
	$ch.UseProxy = $false
	$cli = [Net.Http.HttpClient]::new($ch)
	try {
		return $cli.SendAsync($Req, [Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
	} catch {
		throw "An error occured while initiating an HTTP request; check your network and try again.`n+ $_"
	}
}

function GetJsonResponse {
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[Net.Http.HttpResponseMessage]$Resp
	)
	if (($resp.Content.Headers.ContentType.MediaType -ne 'application/json') -and -not $resp.Content.Headers.ContentType.MediaType.EndsWith('+json')) {
		throw "want application/json, got $($resp.Content.Headers.ContentType.MediaType)"
	}
	return $Resp.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json
}

function GetStringResponse {
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[Net.Http.HttpResponseMessage]$Resp
	)
	return $Resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
}
