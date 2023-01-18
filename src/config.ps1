function ConvertTo-HashTable {
	param (
		[Parameter(ValueFromPipeline)]
		[PSCustomObject]$Object
	)
	$Table = @{}
	$Object.PSObject.Properties | ForEach-Object {
		$V = $_.Value
		if ($V -is [Array]) {
			$V = [System.Collections.ArrayList]$V
		} elseif ($V -is [PSCustomObject]) {
			$V = ($V | ConvertTo-HashTable)
		}
		$Table.($_.Name) = $V
	}
	return $Table
}

function GetAirpowerPath {
	if ($AirpowerPath) {
		$AirpowerPath
	} elseif ($env:AirpowerPath) {
		$env:AirpowerPath
	} else {
		"$env:LocalAppData\Airpower"
	}
}

function GetPwrPullPolicy {
	if ($PwrPullPolicy) {
		$PwrPullPolicy
	} elseif ($env:PwrPullPolicy) {
		$env:PwrPullPolicy
	} else {
		"IfNotPresent"
	}
}

function GetPwrDBPath {
	"$(GetAirpowerPath)\db"
}

function GetPwrTempPath {
	"$(GetAirpowerPath)\temp"
}

function GetPwrContentPath {
	"$(GetAirpowerPath)\content"
}

function ResolvePackagePath {
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[string]$Digest
	)
	return "$(GetPwrContentPath)\$($digest.Substring('sha256:'.Length).Substring(0, 12))"
}

function MakeDirIfNotExist {
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[string]$Path
	)
	if (-not (Test-Path $Path -PathType Container)) {
		New-Item -Path $Path -ItemType Directory
	}
}

function OutPwrDB {
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[Collections.Hashtable]$PwrDB
	)
	MakeDirIfNotExist (GetAirpowerPath)
	$PwrDB |
		ConvertTo-Json -Compress -Depth 10 |
		Out-File -FilePath (GetPwrDBPath) -Encoding 'UTF8' -Force
}

function GetPwrDB {
	$db = GetPwrDBPath
	if (Test-Path $db -PathType Leaf) {
		Get-Content $db -Raw | ConvertFrom-Json | ConvertTo-HashTable
	} else {
		@{
			'pkgdb' = @{}
			'metadatadb' = @{}
		}
	}
}

function FindConfig {
	$path = (Get-Location).Path
	while ($path -ne '') {
		$cfg = "$path\Airpower.ps1"
		if (Test-Path $cfg -PathType Leaf) {
			return $cfg
		}
		$path = $path | Split-Path -Parent
	}
}
