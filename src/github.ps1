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
	$tags = @()
	$digests = @()
	$count = 1
	do {
		$page = HttpRequest "https://api.github.com/repos/$Owner/$Repo/tags?per_page=100&page=$count" -Accept 'application/vnd.github+json' -UserAgent (GetUserAgent) | HttpSend | GetJsonResponse
		$count++
		if ($TagName -and $TagName -ne 'latest') {
			foreach ($p in $page) {
				if ($p.name -match $TagPattern) {
					$tag = $Matches[1]
					for ($i = 2; $i -lt $Matches.Count; $i++) {
						$tag += ".$($Matches[$i])"
					}
					if ($tag -eq $TagName) {
						return $tag, $p.commit.sha
					}
				}
			}
		} else {
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

function DownloadGitHubRelease {
	param (
		[Parameter(Mandatory)]
		[string]$Digest,
		[Parameter(Mandatory)]
		[string]$TagName,
		[Parameter(Mandatory)]
		[string]$UrlFormat,
		[Parameter(Mandatory)]
		[ValidateSet('zip', '7z')]
		[string]$FileExtension,
		[string[]]$IncludeFiles
	)
	$major, $minor, $build, $rev = AsVersion $TagName
	$url = [string]::Format($UrlFormat, $TagName, $major, $minor, $build, $rev)
	try {
		$file, $size = $Digest | DownloadFile -Extension $FileExtension -ArgumentList $url
		$pkgpath = $Digest | ResolvePackagePath
		if ($FileExtension -eq '7z') {
			Expand7zipArchive -File $file -OutDir $pkgpath
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

function AirpowerGitHubPackage {
	param (
		[string]$Owner,
		[string]$Repo,
		[string]$Digest,
		[string]$TagName,
		[Parameter(Mandatory)]
		[string]$TagPattern,
		[Parameter(Mandatory)]
		[string]$UrlFormat,
		[ValidateSet('zip', '7z')]
		[string]$FileExtension = 'zip',
		[string[]]$IncludeFiles
	)
	if ($Digest) {
		return DownloadGitHubRelease -Digest $Digest -TagName $TagName -FileExtension $FileExtension -UrlFormat $UrlFormat -IncludeFiles $IncludeFiles
	} else {
		WriteHost "Retrieving tags from https://github.com/$Owner/$Repo"
		return GetGitHubTags -Owner $Owner -Repo $Repo -TagName $TagName -TagPattern $TagPattern
	}
}
