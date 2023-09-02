. $PSScriptRoot\config.ps1
. $PSScriptRoot\http.ps1
. $PSScriptRoot\progress.ps1

function AsVersion {
	param (
		[Parameter(Mandatory)]
		[string]$Version
	)
	if ($Version -match '^([0-9]+)\.?([0-9]+)?\.?([0-9]+)?[._+]?([0-9]+)?$') {
		$Matches[1], $Matches[2], $Matches[3], $Matches[4]
	}
}

function CompareVersion {
	param (
		[Parameter(Mandatory)]
		[string]$Version,
		[string]$Other
	)
	if ($Other) {
		$vmaj, $vmin, $vbld, $vrev = AsVersion $Version
		$omaj, $omin, $obld, $orev = AsVersion $Other
		if ($vmaj -ne $omaj) {
			$vmaj - $omaj
		} elseif ($vmin -ne $omin) {
			$vmin - $omin
		} elseif ($vbld -ne $obld) {
			$vbld - $obld
		} else {
			$vrev - $orev
		}
	}
	1
}

function GetChunk {
	param (
		[long]$StartByte,
		[Parameter(ValueFromRemainingArguments)]
		[object[]]$ArgumentList
	)
	$range = "bytes=$StartByte-$($StartByte + 536870911)" # Request in 512 MB chunks
	return HttpRequest @ArgumentList -Range $range | HttpSend
}

function DownloadFile {
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[string]$Digest,
		[Parameter(Mandatory)]
		[string]$Extension,
		[Parameter(ValueFromRemainingArguments)]
		[object[]]$ArgumentList
	)
	$sha256 = if ($Digest.StartsWith('sha256:')) { $Digest.Substring(7) } else { $Digest }
	$path = "$(GetPwrTempPath)\$sha256.$Extension"
	if ((Test-Path $path) -and (Get-FileHash $path).Hash.ToLower() -eq $sha256.ToLower()) {
		return $path
	}
	MakeDirIfNotExist (GetPwrTempPath) | Out-Null
	$fs = [IO.File]::Open($path, [IO.FileMode]::OpenOrCreate)
	$fs.Seek(0, [IO.SeekOrigin]::End) | Out-Null
	$bytes = 0
	try {
		do {
			$resp = GetChunk -StartByte $fs.Length @ArgumentList
			if (-not $resp.IsSuccessStatusCode) {
				throw "cannot download blob $($Digest): $($resp.ReasonPhrase)"
			}
			$size = if ($resp.Content.Headers.ContentRange.HasLength) { $resp.Content.Headers.ContentRange.Length } else { $resp.Content.Headers.ContentLength + $fs.Length }
			$bytes += $size
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
	$path, $bytes
}
