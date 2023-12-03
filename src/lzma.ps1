function ExpandLzma {
	param (
		[Parameter(Mandatory)]
		[string]$File,
		[Parameter(Mandatory)]
		[string]$OutDir
	)
	If (-not (Test-Path -Type Container $OutDir)) {
		New-Item -Path $OutDir -ItemType Container
	}
	tar.exe --lzma -xf $File -C $OutDir
	if ($LASTEXITCODE -ne 0) {
		throw "failed to expand lzma archive $File"
	}
}

function WritePwr {
	param (
		[Parameter(Mandatory)]
		[string]$Path,
		[string[]]$IncludeFiles
	)
	$envpath = ''
	foreach ($f in $IncludeFiles) {
		if ($envpath -ne '') {
			$envpath += ';'
		}
		$envpath += (Get-ChildItem -Path $Path -Recurse -Include $f | Select-Object -First 1).DirectoryName
	}
	$object = @{
		env = @{
			path = $envpath
		}
	}
	$text = $object | ConvertTo-Json -Depth 50 -Compress
	[IO.File]::WriteAllText("$Path\.pwr", $text)
}
