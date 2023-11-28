. $PSScriptRoot\download.ps1
. $PSScriptRoot\http.ps1
. $PSScriptRoot\log.ps1
. $PSScriptRoot\lzma.ps1

function GetGitHubTags {
	param (
		[Parameter(Mandatory)]
		[string]$Owner,
		[Parameter(Mandatory)]
		[string]$Repo,
		[string]$TagName,
		[string]$TagPattern
	)
	if ($TagName -and $TagName -ne 'latest') {
		$resp = HttpRequest "https://api.github.com/repos/$Owner/$Repo/git/refs/tags/$TagName" -Accept 'application/vnd.github+json' -UserAgent (GetUserAgent) | HttpSend
		if (-not $resp.IsSuccessStatusCode) {
			throw "no tag $($TagName): $($resp.ReasonPhrase)"
		}
		$j = $resp | GetJsonResponse
		$TagName, $j.object.sha
	}
	$tags = @()
	$digests = @()
	$count = 1
	do {
		$resp = HttpRequest "https://api.github.com/repos/$Owner/$Repo/tags?per_page=100&page=$count" -Accept 'application/vnd.github+json' -UserAgent (GetUserAgent) | HttpSend
		if (-not $resp.IsSuccessStatusCode) {
			throw "failed to retrieve tags: $($resp.ReasonPhrase)"
		}
		$page = $resp | GetJsonResponse
		$count++
		foreach ($p in $page) {
			if ($p.name -match $TagPattern) {
				$tag = $Matches[1]
				for ($i = 2; $i -lt $Matches.Count; $i++) {
					$tag += ".$($Matches[$i])"
				}
				$tags += $tag
				$digests += $p.commit.sha
			}
		}
	} while ($page.Count -gt 0)
	if (-not $TagName) {
		$tags, $digests
	} elseif ($TagName -eq 'latest') {
		if ($tags.Count -gt 0) {
			$latest = $tags[0], $digests[0]
			for ($i = 1; $i -lt $tags.Count; $i += 1) {
				$tag = $tags[$i]
				if ((CompareVersion $latest[0] $tag) -lt 0) {
					$latest = $tag, $digests[$i]
				}
			}
			$latest[0].ToString(), $latest[1]
		}
	}
}

function GetGitHubLatestRelease {
	param (
		[Parameter(Mandatory)]
		[string]$Owner,
		[Parameter(Mandatory)]
		[string]$Repo
	)
	$resp = HttpRequest "https://api.github.com/repos/$Owner/$Repo/releases/latest" -Accept 'application/vnd.github+json' -UserAgent (GetUserAgent) | HttpSend
	if (-not $resp.IsSuccessStatusCode) {
		throw "failed to retrieve latest release: $($resp.ReasonPhrase)"
	}
	$j = $resp | GetJsonResponse
	return GetGitHubTags -Owner $Owner -Repo $Repo -TagName $j.tag_name
}

function DownloadGitHubRelease {
	param (
		[Parameter(Mandatory)]
		[string]$Digest,
		[Parameter(Mandatory)]
		[string]$TagName,
		[Parameter(Mandatory)]
		[string]$UrlFormat,
		[Parameter(Mandatory)]
		[ValidateSet('zip', 'lzma')]
		[string]$Compression,
		[string[]]$IncludeFiles
	)
	$major, $minor, $build, $rev = AsVersion $TagName
	$url = [string]::Format($UrlFormat, $TagName, $major, $minor, $build, $rev)
	try {
		$file, $size = $Digest | DownloadFile -Extension $Compression -ArgumentList $url
		$pkgpath = $Digest | ResolvePackagePath
		if ($Compression -eq 'lzma') {
			ExpandLzmaArchive -File $file -OutDir $pkgpath
		} else {
			Expand-Archive $file $pkgpath
		}
		WritePwr -Path $pkgpath -IncludeFiles $IncludeFiles
	} finally {
		if ($file -and (Test-Path $file -PathType Leaf)) {
			[IO.File]::Delete($file)
		}
	}
	$size
}

function GetGitHubPackage {
	param (
		[Parameter(Mandatory)]
		[string]$Package
	)
	if (-not $AirpowerGitHubPackages) {
		# TODO: shipyard
		$resp = HttpRequest 'https://raw.githubusercontent.com/airpwr/airpwr/gh-pkgs/src/github.json' -UserAgent (GetUserAgent) | HttpSend
		if (-not $resp.IsSuccessStatusCode) {
			throw "failed to retrieve github packages: $($resp.ReasonPhrase)"
		}
		$script:AirpowerGitHubPackages = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json
	}
	$pkg = $AirpowerGitHubPackages.$Package
	if (-not $pkg) {
		throw "no github package: $Package"
	}
	return $pkg
}

function AirpowerResolveGitHubPackage {
	param (
		[Parameter(Mandatory)]
		[string]$Package,
		[string]$TagName,
		[string]$Digest
	)
	$pkg = (GetGitHubPackage $Package)
	if ($Digest) {
		return DownloadGitHubRelease -Digest $Digest -TagName $TagName -Compression $pkg.compression -UrlFormat $pkg.url -IncludeFiles $pkg.files
	} elseif ($pkg.releases -and $TagName -eq 'latest') {
		WriteHost "Retrieving latest release from https://github.com/$($pkg.owner)/$($pkg.repo)/releases/latest"
		return GetGitHubLatestRelease -Owner $pkg.owner -Repo $pkg.repo
	} else {
		WriteHost "Retrieving tags from https://github.com/$($pkg.owner)/$($pkg.repo)"
		return GetGitHubTags -Owner $pkg.owner -Repo $pkg.repo -TagName $TagName -TagPattern $pkg.tag
	}
}
