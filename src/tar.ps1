. $PSScriptRoot\config.ps1
. $PSScriptRoot\progress.ps1

function FromOctalString {
	param (
		[Parameter(ValueFromPipeline)]
		[string]$ASCII
	)
	if (-not $ASCII) {
		return $null
	}
	return [Convert]::ToInt64($ASCII, 8)
}

function ParseTarHeader {
	param (
		[Parameter(Mandatory)]
		[byte[]]$buffer
	)
	return @{
		Filename = [Text.Encoding]::ASCII.GetString($buffer[0..99]).Trim(0)
		Mode = [Text.Encoding]::ASCII.GetString($buffer[100..107]).Trim(0) | FromOctalString
		OwnerID = [Text.Encoding]::ASCII.GetString($buffer[108..115]).Trim(0) | FromOctalString
		GroupID = [Text.Encoding]::ASCII.GetString($buffer[116..123]).Trim(0) | FromOctalString
		Size = [Text.Encoding]::ASCII.GetString($buffer[124..135]).Trim(0) | FromOctalString
		Modified = [Text.Encoding]::ASCII.GetString($buffer[136..147]).Trim(0) | FromOctalString
		Checksum = [Text.Encoding]::ASCII.GetString($buffer[148..155])
		Type = [Text.Encoding]::ASCII.GetString($buffer[156..156]).Trim(0)
		Link = [Text.Encoding]::ASCII.GetString($buffer[157..256]).Trim(0)
		UStar = [Text.Encoding]::ASCII.GetString($buffer[257..262]).Trim(0)
		UStarVersion = [Text.Encoding]::ASCII.GetString($buffer[263..264]).Trim(0)
		Owner = [Text.Encoding]::ASCII.GetString($buffer[265..296]).Trim(0)
		Group = [Text.Encoding]::ASCII.GetString($buffer[297..328]).Trim(0)
		DeviceMajor = [Text.Encoding]::ASCII.GetString($buffer[329..336]).Trim(0)
		DeviceMinor = [Text.Encoding]::ASCII.GetString($buffer[337..344]).Trim(0)
		FilenamePrefix = [Text.Encoding]::ASCII.GetString($buffer[345..499]).Trim(0)
	}
}

function ParsePaxHeader {
	param (
		[Parameter(Mandatory)]
		[IO.Stream]$Source,
		[Parameter(Mandatory)]
		[Collections.Hashtable]$Header
	)
	$buf = New-Object byte[] $Header.Size
	$Source.Read($buf, 0, $Header.Size)
	$content = [Text.Encoding]::UTF8.GetString($buf)
	$xhdr = @{}
	foreach ($line in $content -split "`n") {
		if ($line -match '([0-9]+) ([^=]+)=(.+)') {
			$xhdr += @{
				"$($Matches[2])" = $Matches[3]
			}
		}
	}
	return $xhdr
}

function CopyToFile {
	param (
		[Parameter(Mandatory)]
		[IO.Stream]$Source,
		[Parameter(Mandatory)]
		[string]$FilePath,
		[Parameter(Mandatory)]
		[long]$Size,
		[string]$Digest
	)
	try {
		$copied = 0
		$bufsize = 4096
		$buf = New-Object byte[] $bufsize
		$fs = [IO.File]::Open("\\?\$FilePath", [IO.FileMode]::Create)
		$fs.Seek(0, [IO.SeekOrigin]::Begin) | Out-Null
		$Digest.Substring(0,12) + ': Extracting ' + (GetProgress -Current $Stream.Position -Total $Stream.Length) + '   ' | WritePeriodicConsole
		while ($copied -lt $Size) {
			$amount = if (($Size - $copied) -gt $bufsize) { $bufsize } else { $Size - $copied }
			$Source.Read($buf, 0, $amount) | Out-Null
			$fs.Write($buf, 0, $amount) | Out-Null
			$copied += $amount
		}
	} finally {
		$fs.Dispose()
	}
}

function DecompressTarGz {
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[string]$Path
	)
	$tgz = $Path | Split-Path -Leaf
	$layer = $tgz.Replace('.tar.gz', '')
	$tar = $Path.Replace('.tar.gz', '.tar')
	try {
		$stream = [IO.File]::Open($tar, [IO.FileMode]::OpenOrCreate)
		$stream.Seek(0, [IO.SeekOrigin]::Begin) | Out-Null
		$fs = [IO.File]::Open($Path, [IO.FileMode]::Open)
		$gz = [IO.Compression.GZipStream]::new($fs, [IO.Compression.CompressionMode]::Decompress)
		$task = $gz.CopyToAsync($stream)
		while (-not $task.IsCompleted) {
			$layer.Substring(0,12) + ': Decompressing ' + (GetProgress -Current $fs.Position -Total $fs.Length) | WriteConsole
			Start-Sleep -Milliseconds 125
		}
	} finally {
		$gz.Dispose()
		$fs.Dispose()
		$stream.Dispose()
	}
	return $tar
}

function ExtractTar {
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[string]$Path,
		[Parameter(Mandatory)]
		[string]$Digest
	)
	try {
		$tar = $Path | Split-Path -Leaf
		$layer = $tar.Replace('.tar', '')
		$root = "$(GetPwrContentPath)\$Digest"
		MakeDirIfNotExist -Path $root | Out-Null
		$stream = [IO.File]::Open($Path, [IO.FileMode]::OpenOrCreate)
		$stream.Seek(0, [IO.SeekOrigin]::Begin) | Out-Null
		$buffer = New-Object byte[] 512
		while ($stream.Position -lt $stream.Length) {
			$stream.Read($buffer, 0, 512) | Out-Null
			$hdr = ParseTarHeader $buffer
			$size = if ($xhdr.Size) { $xhdr.Size } else { $hdr.Size }
			$filename = if ($xhdr.Path) { $xhdr.Path } else { $hdr.Filename }
			$file = ($filename -split '/' | Select-Object -Skip 1) -join '\'
			if ($filename.Contains('\..')) {
				throw "suspicious tar filename '$($filename)'"
			}
			if ($hdr.Type -eq [char]53 -and $file -ne '') {
				New-Item -Path "\\?\$root\$file" -ItemType Directory -Force | Out-Null
			}
			if ($hdr.Type -in [char]103, [char]120) {
				$xhdr = ParsePaxHeader -Source $stream -Header $hdr
			} elseif ($hdr.Type -in [char]0, [char]48, [char]55 -and $filename.StartsWith('Files')) {
				CopyToFile -Source $stream -FilePath "$root\$file" -Size $size -Digest $layer
				$xhdr = $null
			} else {
				$stream.Seek($size, [IO.SeekOrigin]::Current) | Out-Null
				$xhdr = $null
			}
			$leftover = $size % 512
			if ($leftover -gt 0) {
				$stream.Seek(512 - ($size % 512), [IO.SeekOrigin]::Current) | Out-Null
			}
		}
	} finally {
		$stream.Dispose()
	}
}
