. $PSScriptRoot\http.ps1
. $PSScriptRoot\config.ps1
. $PSScriptRoot\progress.ps1
. $PSScriptRoot\tar.ps1

function GetDockerRepo {
	return 'airpower/shipyard'
}

function GetAuthToken {
	$auth = "https://auth.docker.io/token?service=registry.docker.io&scope=repository:$(GetDockerRepo):pull"
	$resp = HttpRequest $auth | HttpSend | GetJsonResponse
	return $resp.Token
}

function GetTagsList {
	$api = "/v2/$(GetDockerRepo)/tags/list"
	$endpoint = "https://index.docker.io$api"
	return HttpRequest $endpoint -AuthToken (GetAuthToken) | HttpSend | GetJsonResponse
}

function GetManifest {
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[string]$Ref
	)
	$api = "/v2/$(GetDockerRepo)/manifests/$Ref"
	$params = @{
		URL = "https://index.docker.io$api"
		AuthToken = (GetAuthToken)
		Accept = 'application/vnd.docker.distribution.manifest.v2+json'
	}
	return HttpRequest @params | HttpSend
}

function GetBlob {
	param (
		[Parameter(Mandatory)]
		[string]$Ref,
		[long]$StartByte
	)
	$api = "/v2/$(GetDockerRepo)/blobs/$Ref"
	$params = @{
		URL = "https://index.docker.io$api"
		AuthToken = (GetAuthToken)
		Accept = 'application/octet-stream'
		Range = "bytes=$StartByte-$($StartByte + 536870911)" # Request in 512 MB chunks
	}
	return HttpRequest @params | HttpSend
}

function GetDigestForRef {
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[string]$Ref
	)
	$api = "/v2/$(GetDockerRepo)/manifests/$Ref"
	$params = @{
		URL = "https://index.docker.io$api"
		AuthToken = (GetAuthToken)
		Accept = 'application/vnd.docker.distribution.manifest.v2+json'
		Method = 'HEAD'
	}
	return HttpRequest @params | HttpSend | GetDigest
}

function GetDigest {
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[Net.Http.HttpResponseMessage]$Resp
	)
	return $resp.Headers.GetValues('docker-content-digest')
}

function DebugRateLimit {
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[Net.Http.HttpResponseMessage]$Resp
	)
	if ($resp.Headers.Contains('ratelimit-limit')) {
		Write-Debug "DockerHub RateLimit = $($resp.Headers.GetValues('ratelimit-limit'))"
	}
	if ($resp.Headers.Contains('ratelimit-remaining')) {
		Write-Debug "DockerHub Remaining = $($resp.Headers.GetValues('ratelimit-remaining'))"
	}
}

function GetPackageLayers {
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[Net.Http.HttpResponseMessage]$Resp
	)
	$layers = ($Resp | GetJsonResponse).layers
	$packageLayers = [System.Collections.Generic.List[PSObject]]::new()
	for ($i = 0; $i -lt $layers.Length; $i++) {
		if ($layers[$i].mediaType -eq 'application/vnd.docker.image.rootfs.diff.tar.gzip' -and ($i -gt 0 -or $layer.length -eq 1)) {
			$packageLayers.Add($layers[$i])
		}
	}
	return $packageLayers
}

function GetSize {
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[Net.Http.HttpResponseMessage]$Resp
	)
	$layers = $Resp | GetPackageLayers
	$size = 0
	foreach ($layer in $layers) {
		$size += $layer.size
	}
	return $size
}

function SaveBlob {
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[string]$Digest
	)
	$sha256 = $Digest.Substring('sha256:'.Length)
	$path = "$(GetPwrTempPath)\$sha256.tar.gz"
	if ((Test-Path $path) -and (Get-FileHash $path).Hash -eq $sha256) {
		return $path
	}
	MakeDirIfNotExist (GetPwrTempPath) | Out-Null
	$fs = [IO.File]::Open($path, [IO.FileMode]::OpenOrCreate)
	$fs.Seek(0, [IO.SeekOrigin]::End) | Out-Null
	try {
		do {
			$resp = GetBlob -Ref $Digest -StartByte $fs.Length
			if (-not $resp.IsSuccessStatusCode) {
				throw "cannot download blob $($Digest): $($resp.ReasonPhrase)"
			}
			$size = if ($resp.Content.Headers.ContentRange.HasLength) { $resp.Content.Headers.ContentRange.Length } else { $resp.Content.Headers.ContentLength + $fs.Length }
			$task = $resp.Content.CopyToAsync($fs)
			while (-not $task.IsCompleted) {
				$sha256.Substring(0, 12) + ': Downloading ' + (GetProgress -Current $fs.Length -Total $size) + '  ' | WriteConsole
				Start-Sleep -Milliseconds 125
			}
		} while ($fs.Length -lt $size)
		$sha256.Substring(0, 12) + ': Downloading ' + (GetProgress -Current $fs.Length -Total $size) + '  ' | WriteConsole
	} finally {
		$fs.Close()
	}
	return $path
}
