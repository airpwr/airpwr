Add-Type -AssemblyName System.Net.Http

function HttpRequest {
	param (
		[Parameter(Mandatory)]
		[string]$Url,
		[string]$AuthToken,
		[string]$Accept,
		[string]$UserAgent,
		[ValidateSet('GET', 'HEAD')]
		[string]$Method = 'GET',
		[string]$Range
	)
	$req = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::new($Method), $Url)
	if ($AuthToken) {
		$req.Headers.Authorization = "Bearer $AuthToken"
	}
	if ($Accept) {
		$req.Headers.Accept.Add($Accept)
	}
	if ($UserAgent) {
		$req.Headers.UserAgent.Add($UserAgent)
	}
	if ($Range) {
		$req.Headers.Range = $Range
	}
	$req
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
		throw "An error occured while initiating an HTTP request; check your network connection and try again.`n+ Caused by: $_"
	}
}

function GetJsonResponse {
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[Net.Http.HttpResponseMessage]$Resp
	)
	if (($Resp.Content.Headers.ContentType.MediaType -ne 'application/json') -and -not $Resp.Content.Headers.ContentType.MediaType.EndsWith('+json')) {
		throw "want application/json, got $($Resp.Content.Headers.ContentType.MediaType)"
	}
	return $Resp.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json
}

function GetUserAgent {
	"PowerShell/$($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor)"
}
