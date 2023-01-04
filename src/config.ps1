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

function GetPwrHome {
	if ($PwrHome) {
		$PwrHome
	} elseif ($env:PwrHome) {
		$env:PwrHome
	} else {
		"$env:LocalAppData\pwr"
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
	"$(GetPwrHome)\pwrdb"
}

function GetPwrTempPath {
	"$(GetPwrHome)\tmp"
}

function GetPwrContentPath {
	"$(GetPwrHome)\content"
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
		[Parameter(
			Mandatory = $true,
			ValueFromPipeline = $true)]
		[Collections.Hashtable]$PwrDB
	)
	MakeDirIfNotExist (GetPwrHome)
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
	$path = Resolve-Path .
	while ($path -ne '') {
		$cfg = "$path\pwr.ps1"
		if (Test-Path $cfg -PathType Leaf) {
			return $cfg
		}
		$path = $path | Split-Path -Parent
	}
}