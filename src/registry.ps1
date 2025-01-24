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
	$repo = (GetAirpowerRepo)
	if ($repo) {
		return [PSCustomObject]@{ Name = $repo; Tags = (Get-ChildItem $repo -Directory -Name) }
	}
	$api = "/v2/$(GetDockerRepo)/tags/list"
	$endpoint = "https://index.docker.io$api"
	return HttpRequest $endpoint -AuthToken (GetAuthToken) | HttpSend | GetJsonResponse
}

function GetManifest {
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[string]$Ref,
		[ValidateSet('GET', 'HEAD')]
		[string]$Method = 'GET'
	)
	$repo = (GetAirpowerRepo)
	if ($repo) {
		$file = Join-Path "$repo\$Ref" manifest.json | Get-Item
		if (-not $file.Exists) {
			return [Net.Http.HttpResponseMessage]::new([Net.HttpStatusCode]::NotFound)
		}
		$response = [Net.Http.HttpResponseMessage]::new([Net.HttpStatusCode]::OK)
		$response.Headers.Add('Docker-Content-Digest', "sha256:$((Get-FileHash $file).Hash.ToLower())")
		if ($Method -eq 'GET') {
			$response.Content = [Net.Http.ByteArrayContent]::new([IO.File]::ReadAllBytes($file))
			$response.Content.Headers.ContentType = [Net.Http.Headers.MediaTypeHeaderValue]::new('application/json')
		}
		return $response
	}
	$api = "/v2/$(GetDockerRepo)/manifests/$Ref"
	$params = @{
		URL = "https://index.docker.io$api"
		AuthToken = (GetAuthToken)
		Accept = 'application/vnd.docker.distribution.manifest.v2+json'
		Method = $Method
	}
	return HttpRequest @params | HttpSend
}

function GetBlob {
	param (
		[Parameter(Mandatory)]
		[string]$Ref,
		[long]$StartByte
	)
	$repo = (GetAirpowerRepo)
	if ($repo) {
		$file = Get-ChildItem $repo -Depth 1 -Recurse "$($Ref.Substring('sha256:'.Length)).tar.gz"
		if (-not $file -or -not $file.Exists -or $file.Length -le $StartByte) {
			return [Net.Http.HttpResponseMessage]::new([Net.HttpStatusCode]::NotFound)
		}
		$fs = [IO.File]::Open($file.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
		$fs.Seek($StartByte, [IO.SeekOrigin]::Begin) | Out-Null
		$response = [Net.Http.HttpResponseMessage]::new([Net.HttpStatusCode]::OK)
		$response.Headers.Add('Docker-Content-Digest', "sha256:$((Get-FileHash $file.FullName).Hash.ToLower())")
		$response.Content = [Net.Http.StreamContent]::new($fs)
		$response.Content.Headers.ContentType = [Net.Http.Headers.MediaTypeHeaderValue]::new('application/octet-stream')
		$response.Content.Headers.ContentRange = [Net.Http.Headers.ContentRangeHeaderValue]::new($StartByte, $file.Length - 1, $file.Length)
		return $response
	}
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
	return $Ref | GetManifest -Method HEAD | GetDigest
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
		if ($layers[$i].mediaType -eq 'application/vnd.docker.image.rootfs.diff.tar.gzip' -and ($i -gt 0 -or $layers.Length -eq 1)) {
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
		[string]$Digest,
		[String]$Output
	)
	$sha256 = $Digest.Substring('sha256:'.Length)
	$path = "$(if ($Output) { Resolve-Path $Output } else { GetPwrTempPath })\$sha256.tar.gz"
	if ((Test-Path $path) -and (Get-FileHash $path).Hash -eq $sha256) {
		return $path
	}
	MakeDirIfNotExist (Split-Path $path) | Out-Null
	$fs = [IO.File]::Open($path, [IO.FileMode]::OpenOrCreate)
	$fs.Seek(0, [IO.SeekOrigin]::End) | Out-Null
	try {
		do {
			$resp = GetBlob -Ref $Digest -StartByte $fs.Length
			try {
				if (-not $resp.IsSuccessStatusCode) {
					throw "cannot download blob $($Digest): $($resp.ReasonPhrase)"
				}
				$size = if ($resp.Content.Headers.ContentRange.HasLength) { $resp.Content.Headers.ContentRange.Length } else { $resp.Content.Headers.ContentLength + $fs.Length }
				$task = $resp.Content.CopyToAsync($fs)
				while (-not $task.IsCompleted) {
					$sha256.Substring(0, 12) + ': Downloading ' + (GetProgress -Current $fs.Length -Total $size) + '  ' | WriteConsole
					Start-Sleep -Milliseconds 125
				}
			} finally {
				$resp.Dispose()
			}
		} while ($fs.Length -lt $size)
		$sha256.Substring(0, 12) + ': Downloading ' + (GetProgress -Current $fs.Length -Total $size) + '  ' | WriteConsole
	} finally {
		$fs.Close()
	}
	return $path
}
