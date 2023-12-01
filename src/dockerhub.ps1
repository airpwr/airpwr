. $PSScriptRoot\download.ps1
. $PSScriptRoot\http.ps1
. $PSScriptRoot\config.ps1
. $PSScriptRoot\progress.ps1
. $PSScriptRoot\tar.ps1

function AsRemotePackage {
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[string]$RegistryTag
	)
	if ($RegistryTag -match '(.*)-([0-9].+)') {
		return @{
			Package = $Matches[1]
			Tag = if ($Matches[2] -in 'latest', '', $null) { 'latest' } else { $Matches[2] }
		}
	}
	throw "failed to parse registry tag: $RegistryTag"
}

function GetDockerRegistry {
	'https://index.docker.io/v2'
}

function GetDockerRepo {
	'airpower/shipyard'
}

function GetAuthToken {
	$auth = "https://auth.docker.io/token?service=registry.docker.io&scope=repository:$(GetDockerRepo):pull"
	(HttpRequest $auth | HttpSend | GetJsonResponse).Token
}

function GetTagsList {
	$endpoint = "$(GetDockerRegistry)/$(GetDockerRepo)/tags/list"
	HttpRequest $endpoint -AuthToken (GetAuthToken) | HttpSend | GetJsonResponse
}

function GetManifest {
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[string]$Ref
	)
	$params = @{
		Url = "$(GetDockerRegistry)/$(GetDockerRepo)/manifests/$Ref"
		AuthToken = (GetAuthToken)
		Accept = 'application/vnd.docker.distribution.manifest.v2+json'
	}
	HttpRequest @params | HttpSend
}

function GetDigestForRef {
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[string]$Ref
	)
	$params = @{
		Url = "$(GetDockerRegistry)/$(GetDockerRepo)/manifests/$Ref"
		AuthToken = (GetAuthToken)
		Accept = 'application/vnd.docker.distribution.manifest.v2+json'
		Method = 'HEAD'
	}
	HttpRequest @params | HttpSend | GetDigest
}

function GetDigest {
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[Net.Http.HttpResponseMessage]$Resp
	)
	$resp.Headers.GetValues('docker-content-digest')
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
	$packageLayers
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
	$size
}

function SavePackage {
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[Net.Http.HttpResponseMessage]$Resp
	)
	[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
	SetCursorVisible $false
	try {
		$layers = $Resp | GetPackageLayers
		$digest = $Resp | GetDigest
		$files = @()
		$bytes = 0
		foreach ($layer in $layers) {
			try {
				$url = "$(GetDockerRegistry)/$(GetDockerRepo)/blobs/$($layer.Digest)"
				$auth = (GetAuthToken)
				$accept = 'application/octet-stream'
				$file, $size = $layer.Digest | DownloadFile -Extension 'tar.gz' -ArgumentList $url $auth $accept | ExtractTarGz -Digest $digest
				"$($layer.Digest | AsDigestString): Pull complete" + ' ' * 60 | WriteConsole
				$files += $file
				$bytes += $size
			} finally {
				WriteConsole "`n"
			}
		}
		foreach ($f in $files) {
			[IO.File]::Delete($f)
		}
		$bytes
	} finally {
		SetCursorVisible $true
	}
}

function AirpowerResolveDockerHubPackage {
	param (
		[string]$Package,
		[string]$TagName,
		[string]$Digest
	)
	if ($Package) {
	} else {
		$pkgs = [hashtable]@{}
		foreach ($tag in (GetTagsList).tags) {
			$pkg = $tag | AsRemotePackage
			$pkgs.$($pkg.Package) += @($pkg.Tag)
		}
		$pkgs
	}
}
