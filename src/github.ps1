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
		[Parameter(Mandatory)]
		[string]$TagPattern
	)
	$lock = [Db]::Lock(('remotedb', 'github', $Owner, $Repo))
	try {
		$pkgs = $lock.Get() | ConvertTo-HashTable
		$tags = $pkgs.Tags
		$digests = $pkgs.Digests
		if ($TagName -and $TagName -ne 'latest') {
			$i = if ($tags) { $tags.IndexOf($TagName) } else { -1 }
			if ($i -ge 0) {
				return $tags[$i], $digests[$i]
			}
			$resp = HttpRequest "https://api.github.com/repos/$Owner/$Repo/git/refs/tags/$TagName" -Accept 'application/vnd.github+json' -UserAgent (GetUserAgent) | HttpSend
			if (-not $resp.IsSuccessStatusCode) {
				throw "no tag $($TagName): $($resp.ReasonPhrase)"
			}
			$j = $resp | GetJsonResponse
			$digest = $j.object.sha
			if ($TagName -notmatch $TagPattern) {
				throw "release tag $TagName does not match pattern $TagPattern"
			}
			$tag = $Matches[1]
			for ($i = 2; $i -lt $Matches.Count; $i++) {
				$tag += ".$($Matches[$i])"
			}
			if ($tag -notin $tags) {
				$lock.Put(@{
					Tags = $tags + @($tag)
					Digests = $digests + @($digest)
				})
				$lock.Unlock()
			}
			return $tag, $digest
		}
		$resp = HttpRequest "https://api.github.com/repos/$Owner/$Repo/tags?per_page=100&page=1" -Accept 'application/vnd.github+json' -UserAgent (GetUserAgent) | HttpSend
		if (-not $resp.IsSuccessStatusCode) {
			throw "failed to retrieve tags: $($resp.ReasonPhrase)"
		}
		$page = $resp | GetJsonResponse
		foreach ($p in $page) {
			if ($p.name -match $TagPattern) {
				$tag = $Matches[1]
				for ($i = 2; $i -lt $Matches.Count; $i++) {
					$tag += ".$($Matches[$i])"
				}
				if ($tag -notin $tags) {
					$tags += @($tag)
					$digests += @($p.commit.sha)
				}
			}
		}
		$lock.Put(@{
			Tags = $tags
			Digests = $digests
		})
		$lock.Unlock()
		if (-not $TagName) {
			$tags, $digests
		} elseif ($TagName -eq 'latest') {
			if (-not $tags) {
				throw "no github tags found for $TagName"
			} elseif ($tags.Count -gt 0) {
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
	} finally {
		$lock.Revert()
	}
}

function GetGitHubLatestRelease {
	param (
		[Parameter(Mandatory)]
		[string]$Owner,
		[Parameter(Mandatory)]
		[string]$Repo,
		[Parameter(Mandatory)]
		[string]$TagPattern
	)
	WriteHost "Retrieving latest release from https://github.com/$Owner/$Repo/releases/latest"
	$resp = HttpRequest "https://api.github.com/repos/$Owner/$Repo/releases/latest" -Accept 'application/vnd.github+json' -UserAgent (GetUserAgent) | HttpSend
	if (-not $resp.IsSuccessStatusCode) {
		throw "failed to retrieve latest release: $($resp.ReasonPhrase)"
	}
	$j = $resp | GetJsonResponse
	GetGitHubTags -Owner $Owner -Repo $Repo -TagName $j.tag_name -TagPattern $TagPattern
}

function DownloadGitHubRelease {
	param (
		[Parameter(Mandatory)]
		[string]$Digest,
		[Parameter(Mandatory)]
		[string]$Tag,
		[Parameter(Mandatory)]
		[string]$UrlFormat,
		[Parameter(Mandatory)]
		[ValidateSet('zip', 'lzma')]
		[string]$Compression,
		[string[]]$IncludeFiles
	)
	$major, $minor, $build, $rev = AsVersion $Tag
	$url = [string]::Format($UrlFormat, $Tag, $major, $minor, $build, $rev)
	try {
		$file, $size = $Digest | DownloadFile -Extension $Compression -ArgumentList $url
		$pkgpath = $Digest | ResolvePackagePath
		if ($Compression -eq 'lzma') {
			ExpandLzmaArchive -File $file -OutDir $pkgpath
		} else {
			Expand-Archive $file $pkgpath
		}
		WritePwr -Path $pkgpath -IncludeFiles $IncludeFiles
		[long]$size
	} finally {
		if ($file -and (Test-Path $file -PathType Leaf)) {
			[IO.File]::Delete($file)
		}
	}
}

function GetGitHubPackages {
	if (-not $AirpowerGitHubPackages) {
		# TODO: shipyard url
		$resp = HttpRequest 'https://raw.githubusercontent.com/airpwr/airpwr/gh-pkgs/src/github.json' -UserAgent (GetUserAgent) | HttpSend
		if (-not $resp.IsSuccessStatusCode) {
			throw "failed to retrieve github packages: $($resp.ReasonPhrase)"
		}
		$script:AirpowerGitHubPackages = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json
	}
	$AirpowerGitHubPackages
}

function GetGitHubPackage {
	param (
		[Parameter(Mandatory)]
		[string]$Package
	)
	$pkg = (GetGitHubPackages).$Package
	if (-not $pkg) {
		throw "no github package: $Package"
	}
	return $pkg
}

function AirpowerResolveGitHubTags {
	$pkgs = [hashtable]@{}
	foreach ($pkg in (GetGitHubPackages).PSObject.Properties) {
		$tags, $digests = GetGitHubTags -Owner $pkg.Value.owner -Repo $pkg.Value.repo -TagPattern $pkg.Value.tag
		$pkgs.$($pkg.Name) = $tags
	}
	$pkgs
}

function AirpowerResolveGitHubDigest {
	param (
		[Parameter(Mandatory)]
		[string]$Package,
		[Parameter(Mandatory)]
		[string]$TagName
	)
	$pkg = (GetGitHubPackage $Package)
	if ($pkg.releases -and $TagName -eq 'latest') {
		GetGitHubLatestRelease -Owner $pkg.owner -Repo $pkg.repo -TagPattern $pkg.tag
	} else {
		WriteHost "Retrieving tags from https://github.com/$($pkg.owner)/$($pkg.repo)"
		GetGitHubTags -Owner $pkg.owner -Repo $pkg.repo -TagName $TagName -TagPattern $pkg.tag
	}
}

function AirpowerResolveGitHubPackage {
	param (
		[Parameter(Mandatory)]
		[string]$Package,
		[Parameter(Mandatory)]
		[string]$Tag,
		[Parameter(Mandatory)]
		[string]$Digest
	)
	$pkg = (GetGitHubPackage $Package)
	DownloadGitHubRelease -Digest $Digest -Tag $Tag -Compression $pkg.compression -UrlFormat $pkg.url -IncludeFiles $pkg.files
}
