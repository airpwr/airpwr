function Expand7zipArchive {
	param (
		[Parameter(Mandatory)]
		[string]$File,
		[Parameter(Mandatory)]
		[string]$OutDir
	)
	$File, $OutDir | Out-Null
	Invoke-AirpowerExec -Packages '7-zip:9.20' -ScriptBlock {
		7za.exe x -o"$OutDir" $File | Out-Null
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
