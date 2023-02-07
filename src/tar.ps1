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
		[byte[]]$Buffer
	)
	return @{
		Filename = [Text.Encoding]::ASCII.GetString($Buffer[0..99]).Trim(0)
		Mode = [Text.Encoding]::ASCII.GetString($Buffer[100..107]).Trim(0) | FromOctalString
		OwnerID = [Text.Encoding]::ASCII.GetString($Buffer[108..115]).Trim(0) | FromOctalString
		GroupID = [Text.Encoding]::ASCII.GetString($Buffer[116..123]).Trim(0) | FromOctalString
		Size = [Text.Encoding]::ASCII.GetString($Buffer[124..135]).Trim(0) | FromOctalString
		Modified = [Text.Encoding]::ASCII.GetString($Buffer[136..147]).Trim(0) | FromOctalString
		Checksum = [Text.Encoding]::ASCII.GetString($Buffer[148..155])
		Type = [Text.Encoding]::ASCII.GetString($Buffer[156..156]).Trim(0)
		Link = [Text.Encoding]::ASCII.GetString($Buffer[157..256]).Trim(0)
		UStar = [Text.Encoding]::ASCII.GetString($Buffer[257..262]).Trim(0)
		UStarVersion = [Text.Encoding]::ASCII.GetString($Buffer[263..264]).Trim(0)
		Owner = [Text.Encoding]::ASCII.GetString($Buffer[265..296]).Trim(0)
		Group = [Text.Encoding]::ASCII.GetString($Buffer[297..328]).Trim(0)
		DeviceMajor = [Text.Encoding]::ASCII.GetString($Buffer[329..336]).Trim(0)
		DeviceMinor = [Text.Encoding]::ASCII.GetString($Buffer[337..344]).Trim(0)
		FilenamePrefix = [Text.Encoding]::ASCII.GetString($Buffer[345..499]).Trim(0)
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
	$Source.ReadExactly($buf, 0, $Header.Size)
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

function ExtractTarGz {
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[string]$Path,
		[Parameter(Mandatory)]
		[string]$Digest
	)
	$tgz = $Path | Split-Path -Leaf
	$layer = $tgz.Replace('.tar.gz', '')
	if ($layer -ne (Get-FileHash $Path).Hash) {
		[IO.File]::Delete($Path)
		throw "removed $Path because it had corrupted data"
	}
	$fs = [IO.File]::OpenRead($Path)
	try {
		$gz = [IO.Compression.GZipStream]::new($fs, [IO.Compression.CompressionMode]::Decompress, $true)
		try {
			$gz | ExtractTar -Digest $Digest
		} finally {
			$gz.Dispose()
		}
	} finally {
		$fs.Dispose()
	}
	return $Path
}

function ExtractTar {
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[IO.Compression.GZipStream]$Source,
		[Parameter(Mandatory)]
		[string]$Digest
	)
	$root = ResolvePackagePath -Digest $Digest
	MakeDirIfNotExist -Path $root | Out-Null
	$buffer = New-Object byte[] 512
	try {
		while ($true) {
			{ $layer.Substring(0, 12) + ': Extracting ' + (GetProgress -Current $Source.BaseStream.Position -Total $Source.BaseStream.Length) + '   ' } | WritePeriodicConsole
			try {
				$Source.ReadExactly($buffer, 0, 512)
			} catch [IO.EndOfStreamException] {
				break
			}
			$hdr = ParseTarHeader $buffer
			$size = if ($xhdr.Size) { $xhdr.Size } else { $hdr.Size }
			$filename = if ($xhdr.Path) { $xhdr.Path } else { $hdr.Filename }
			$file = ($filename -split '/' | Select-Object -Skip 1) -join '\'
			if ($filename.Contains('\..')) {
				throw "suspicious tar filename '$($filename)'"
			}
			if ($hdr.Type -eq [char]53 -and $file -ne '') {
				New-Item -Path "\\?\$root\$file" -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
			}
			if ($hdr.Type -in [char]103, [char]120) {
				$xhdr = ParsePaxHeader -Source $Source -Header $hdr
			} elseif ($hdr.Type -in [char]0, [char]48, [char]55 -and $filename.StartsWith('Files')) {
				$buf = New-Object byte[] $size
				$Source.ReadExactly($buf, 0, $size)
				$fs = [IO.File]::Open("\\?\$root\$file", [IO.FileMode]::Create, [IO.FileAccess]::Write)
				try {
					if ($write) {
						$write.Wait()
						if ($write.IsFaulted) {
							throw $write.Exception
						}
						$writefs.Dispose()
					}
				} catch {
					$fs.Dispose()
					throw
				}
				$writefs = $fs
				$write = $writefs.WriteAsync($buf, 0, $size)
				$xhdr = $null
			} else {
				if ($size -gt 0) {
					$Source.ReadExactly((New-Object byte[] $size), 0, $size)
				}
				$xhdr = $null
			}
			$leftover = $size % 512
			if ($leftover -gt 0) {
				$Source.ReadExactly($buffer, 0, 512 - $leftover)
			}
		}
		if ($write) {
			$write.Wait()
			if ($write.IsFaulted) {
				throw $write.Exception
			}
		}
	} finally {
		if ($writefs) {
			$writefs.Dispose()
		}
	}
	$layer.Substring(0, 12) + ': Extracting ' + (GetProgress -Current $Source.BaseStream.Length -Total $Source.BaseStream.Length) + '   ' | WriteConsole
}
