. $PSScriptRoot\config.ps1
. $PSScriptRoot\package.ps1

function GetSessionState {
	return @{
		Vars = (Get-Variable -Scope Global | ForEach-Object { ConvertTo-HashTable $_ } )
		Env = (Get-Item Env:)
	}
}

function SaveSessionState {
	param (
		[Parameter(Mandatory)]
		[string]$GUID
	)
	Set-Variable -Name "AirpowerSaveState_$GUID" -Value (GetSessionState) -Scope Global
}

function ClearSessionState {
	param (
		[Parameter(Mandatory)]
		[string]$GUID
	)
	$default = "AirpowerSaveState_$GUID", '__LastHistoryId', '__VSCodeOriginalPrompt', '__VSCodeOriginalPSConsoleHostReadLine', '?', '^', '$', 'args', 'ConfirmPreference', 'DebugPreference', 'EnabledExperimentalFeatures', 'Error', 'ErrorActionPreference', 'ErrorView', 'ExecutionContext', 'false', 'FormatEnumerationLimit', 'HOME', 'Host', 'InformationPreference', 'input', 'IsCoreCLR', 'IsLinux', 'IsMacOS', 'IsWindows', 'MaximumHistoryCount', 'MyInvocation', 'NestedPromptLevel', 'null', 'OutputEncoding', 'PID', 'PROFILE', 'ProgressPreference', 'PSBoundParameters', 'PSCommandPath', 'PSCulture', 'PSDefaultParameterValues', 'PSEdition', 'PSEmailServer', 'PSHOME', 'PSScriptRoot', 'PSSessionApplicationName', 'PSSessionConfigurationName', 'PSSessionOption', 'PSStyle', 'PSUICulture', 'PSVersionTable', 'PWD', 'ShellId', 'StackTrace', 'true', 'VerbosePreference', 'WarningPreference', 'WhatIfPreference', 'ConsoleFileName', 'MaximumAliasCount', 'MaximumDriveCount', 'MaximumErrorCount', 'MaximumFunctionCount', 'MaximumVariableCount'
	foreach ($v in (Get-Variable -Scope Global)) {
		if ($v.name -notin $default) {
			Remove-Variable -Name $v.name -Scope Global -Force -ErrorAction SilentlyContinue
		}
	}
	foreach ($k in [Environment]::GetEnvironmentVariables([EnvironmentVariableTarget]::User).keys) {
		if ($k -notin 'temp', 'tmp', 'AirpowerPath') {
			Remove-Item "env:$k" -Force -ErrorAction SilentlyContinue
		}
	}
	Remove-Item 'env:AirpowerLoadedPackages' -Force -ErrorAction SilentlyContinue
}

function RestoreSessionState {
	param (
		[Parameter(Mandatory)]
		[string]$GUID
	)
	$state = (Get-Variable "AirpowerSaveState_$GUID").value
	foreach ($v in $state.vars) {
		Set-Variable -Name $v.name -Value $v.value -Scope Global -Force -ErrorAction SilentlyContinue
	}
	foreach ($e in $state.env) {
		Set-Item -Path "env:$($e.name)" -Value $e.value -Force -ErrorAction SilentlyContinue
	}
	Remove-Variable "AirpowerSaveState_$GUID" -Force -Scope Global -ErrorAction SilentlyContinue
}

function GetPackageDefinition {
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[string]$Digest
	)
	if (-not $Digest) {
		return $null
	}
	$root = ResolvePackagePath -Digest $Digest
	return (Get-Content -Raw "$root\.pwr").Replace('${.}', $root.Replace('\', '\\')) | ConvertFrom-Json | ConvertTo-HashTable
}

function ConfigurePackage {
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[Collections.Hashtable]$Pkg,
		[switch]$AppendPath
	)
	$defn = $Pkg.Digest | GetPackageDefinition
	$cfg = if ($Pkg.Config -eq 'default') { $defn } else { $defn.$($Pkg.Config) }
	if (-not $cfg) {
		throw "configuration '$($Pkg.Config)' not found for $($Pkg.Package):$($Pkg.Tag | AsTagString)"
	}
	foreach ($k in $cfg.env.keys) {
		if ($k -eq 'Path') {
			if ($AppendPath) {
				$post = "$(if ($env:Path -and -not $env:Path.StartsWith(';')) { ';' })$env:Path"
			} else {
				$pre = "$env:Path$(if ($env:Path) { ';' })"
			}
		} else {
			$pre = $post = ''
		}
		Set-Item "env:$k" "$pre$($cfg.env.$k)$post"
	}
}

function LoadPackage {
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[Collections.Hashtable]$Pkg
	)
	$digest = $Pkg | ResolvePackageDigest
	$ref = "$($Pkg.Package):$($Pkg.Tag | AsTagString)"
	if (-not $digest) {
		throw "no such package $ref"
	}
	$Pkg.Digest = $digest
	WriteHost "Digest: $digest"
	if ($digest -notin ($env:AirpowerLoadedPackages -split ';')) {
		$Pkg | ConfigurePackage
		$env:AirpowerLoadedPackages += "$(if ($env:AirpowerLoadedPackages) { ';' })$digest"
		WriteHost "Status: Session configured for $ref"
	} else {
		WriteHost "Status: Session is up to date for $ref"
	}
}

function ExecuteScript {
	param (
		[Parameter(Mandatory)]
		[scriptblock]$ScriptBlock,
		[Parameter(Mandatory)]
		[Collections.Hashtable[]]$Pkgs
	)
	$GUID = New-Guid
	SaveSessionState $GUID
	try {
		ClearSessionState $GUID
		$env:Path = ''
		foreach ($pkg in $Pkgs) {
			$pkg.digest = $pkg | ResolvePackageDigest
			$ref = "$($Pkg.Package):$($Pkg.Tag | AsTagString)"
			if (-not $pkg.digest) {
				throw "no such package $ref"
			}
			$pkg | ConfigurePackage -AppendPath
		}
		$env:Path = "$(if ($env:Path) { "$env:Path;" })$env:SYSTEMROOT;$env:SYSTEMROOT\System32;$PSHOME"
		& $ScriptBlock
	} finally {
		RestoreSessionState $GUID
	}
}
