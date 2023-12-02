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
	$Resp.Headers.GetValues('docker-content-digest')
}

function DebugRateLimit {
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[Net.Http.HttpResponseMessage]$Resp
	)
	if ($Resp.Headers.Contains('ratelimit-limit')) {
		Write-Debug "DockerHub RateLimit = $($Resp.Headers.GetValues('ratelimit-limit'))"
	}
	if ($Resp.Headers.Contains('ratelimit-remaining')) {
		Write-Debug "DockerHub Remaining = $($Resp.Headers.GetValues('ratelimit-remaining'))"
	}
	$Resp
}

function GetPackageLayers {
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[Net.Http.HttpResponseMessage]$Resp
	)
	$layers = ($Resp | GetJsonResponse).layers
	for ($i = 0; $i -lt $layers.Length; $i++) {
		if ($layers[$i].mediaType -eq 'application/vnd.docker.image.rootfs.diff.tar.gzip' -and ($i -gt 0 -or $layer.length -eq 1)) {
			$layers[$i]
		}
	}
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
		[Net.Http.HttpResponseMessage]$Resp,
		[Parameter(Mandatory)]
		[string]$Digest
	)
	[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
	SetCursorVisible $false
	try {
		$layers = $Resp | GetPackageLayers
		$files = @()
		$bytes = 0
		foreach ($layer in $layers) {
			try {
				$url = "$(GetDockerRegistry)/$(GetDockerRepo)/blobs/$($layer.Digest)"
				$auth = (GetAuthToken)
				$accept = 'application/octet-stream'
				$file, $size = $layer.Digest | DownloadFile -Extension 'tar.gz' -ArgumentList $url, $auth, $accept
				$file | ExtractTarGz -Digest $Digest
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
		[long]$bytes
	} finally {
		SetCursorVisible $true
	}
}

function AirpowerResolveDockerHubTags {
	$pkgs = [hashtable]@{}
	foreach ($tag in (GetTagsList).tags) {
		$pkg = $tag | AsRemotePackage
		$pkgs.$($pkg.Package) += @($pkg.Tag)
	}
	$pkgs
}

function AirpowerResolveDockerHubDigest {
	param (
		[Parameter(Mandatory)]
		[string]$Package,
		[Parameter(Mandatory)]
		[string]$TagName
	)
	WriteHost "Retrieving tags from $(GetDockerRegistry)/$(GetDockerRepo)"
	if ($TagName -ne 'latest') {
		foreach ($tag in (GetTagsList).tags) {
			$pkg = $tag | AsRemotePackage
			if ($pkg.Package -eq $Package -and $pkg.Tag -eq $TagName) {
				return $tag | GetDigestForRef
			}
		}
	} else {
		foreach ($tag in (GetTagsList).tags) {
			$pkg = $tag | AsRemotePackage
			$pkgtag = [Tag]::new($pkg.Tag)
			if ($pkg.Package -eq $Package -and (-not $latest -or $latest.Tag -lt $pkgtag)) {
				$latest = @{
					RegistryTag = $tag
					Tag = $pkgtag
				}
			}
		}
		if ($latest) {
			$digest = ($latest.RegistryTag | GetDigestForRef).Substring(7)
			return $latest.Tag.ToString(), $digest
		}
	}
	throw "found no tags for ${Package}:$TagName in $(GetDockerRegistry)/$(GetDockerRepo)"
}

function AirpowerResolveDockerHubPackage {
	param (
		[Parameter(Mandatory)]
		[string]$Package,
		[Parameter(Mandatory)]
		[string]$Tag,
		[Parameter(Mandatory)]
		[string]$Digest
	)
	"$Package-$Tag" | GetManifest | DebugRateLimit | SavePackage -Digest $Digest
}
