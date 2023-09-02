function ConvertTo-HashTable {
	param (
		[Parameter(ValueFromPipeline)]
		[PSCustomObject]$Object
	)
	if ($null -eq $Object) {
		return
	}
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

function GetAirpowerPullPolicy {
	if ($AirpowerPullPolicy) {
		$AirpowerPullPolicy
	} elseif ($env:AirpowerPullPolicy) {
		$env:AirpowerPullPolicy
	} else {
		"IfNotPresent"
	}
}

function GetAirpowerAutoprune {
	if ($AirpowerAutoprune) {
		$AirpowerAutoprune
	} elseif ($env:AirpowerAutoprune) {
		$env:AirpowerAutoprune
	}
}

function GetPwrDBPath {
	"$(GetAirpowerPath)\cache"
}

function GetPwrTempPath {
	"$(GetAirpowerPath)\temp"
}

function GetPwrContentPath {
	"$(GetAirpowerPath)\content"
}

function AsDigestString {
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[string]$Digest
	)
	if ($Digest.StartsWith('sha256:')) {
		return $Digest.Substring(7, 12)
	}
	return $Digest.Substring(0, 12)
}

function ResolvePackagePath {
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[string]$Digest
	)
	"$(GetPwrContentPath)\$($Digest | AsDigestString)"
}

function MakeDirIfNotExist {
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[string]$Path
	)
	New-Item -Path $Path -ItemType Directory -ErrorAction Ignore
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

function LoadConfig {
	$cfg = FindConfig
	if ($cfg) {
		. $cfg
	}
}
