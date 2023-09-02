. $PSScriptRoot\..\download.ps1
. $PSScriptRoot\..\lzma.ps1
. $PSScriptRoot\..\progress.ps1

function AirpowerPackage7-zip {
	param (
		[string]$TagName,
		[string]$Digest
	)
	$all = @(
		@('23.01', '26cb6e9f56333682122fafe79dbcdfd51e9f47cc7217dccd29ac6fc33b5598cd', '7z.exe'),
		@('22.01', 'b055fee85472921575071464a97a79540e489c1c3a14b9bdfbdbab60e17f36e4', '7z.exe'),
		@('19.00', '0f5d4dbbe5e55b7aa31b91e5925ed901fdf46a367491d81381846f05ad54c45e', '7z.exe'),
		@('16.04', '9bb4dc4fab2a2a45c15723c259dc2f7313c89a5ac55ab7c3f76bba26edc8bcaa', '7z.exe'),
		@('9.20', '2a3afe19c180f8373fa02ff00254d5394fec0349f5804e0ad2f6067854ff28ac', '7za.exe')
	)
	$latest = $all[0]
	if ($Digest) {
		if ($TagName -eq 'latest' -or $TagName -eq $latest[0]) {
			$t = $latest
		} else {
			for ($i = 1; $i -lt $all.Count; $i++) {
				$a = $all[$i]
				if ($TagName -eq $a[0]) {
					$t = $a
					break
				}
			}
			if (-not $t) {
				return -1
			}
		}
		$hash = $t[1]
		$inc = $t[2]
		$lzma = $inc -eq '7z.exe'
		$tag = $hash.Substring(0, 12)
		$ext = if ($lzma) { '7z' } else { 'zip' }
		$url = "https://www.7-zip.org/a/7z$(if ($lzma) {
			"$($t[0].Replace('.', ''))-x64.exe"
		} else {
			"a$($t[0].Replace('.', '')).zip"
		})"
		try {
			$file, $size = $hash | DownloadFile -Extension $ext -ArgumentList $url
			WriteConsole ''
			$dig = (Get-FileHash -Algorithm SHA256 $file).Hash.ToLower()
			if ($dig -ne $hash) {
				Write-Error "7-zip bad digest $dig (should be $hash)"
			}
			$outdir = "$(GetPwrContentPath)\$tag"
			if ($lzma) {
				Expand7zipArchive -File $file -OutDir $outdir
			} else {
				Expand-Archive $file $outdir
			}
			WritePwr -Path $outdir -IncludeFiles $inc
			return $size
		} finally {
			if ($file -and (Test-Path $file -PathType Leaf)) {
				[IO.File]::Delete($file)
			}
		}
	} else {
		if ($TagName -eq 'latest' -or $TagName -eq $latest[0]) {
			$latest[0], $latest[1]
		} elseif ($TagName -eq 'all') {
			$tags = @()
			$digests = @()
			foreach ($a in $all) {
				$tags += $a[0]
				$digests += $a[1]
			}
			$tags, $digests
		} else {
			for ($i = 1; $i -lt $all.Count; $i++) {
				$t = $all[$i]
				if ($TagName -eq $t[0]) {
					return $t[0], $t[1]
				}
			}
		}
	}
}
