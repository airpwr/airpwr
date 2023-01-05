. $PSScriptRoot\config.ps1
. $PSScriptRoot\package.ps1

function GetSessionState {
	return @{
		Vars = (Get-Variable -Scope Global | ForEach-Object { ConvertTo-HashTable $_ } )
		Env = (Get-Item Env:)
	}
}

function SaveSessionState {
	Set-Variable -Name 'PwrSaveState' -Value (GetSessionState) -Scope Global
}

function ClearSessionState {
	$default = '__LastHistoryId', '__VSCodeOriginalPrompt', '__VSCodeOriginalPSConsoleHostReadLine', '?', '^', '$', 'args', 'ConfirmPreference', 'DebugPreference', 'EnabledExperimentalFeatures', 'Error', 'ErrorActionPreference', 'ErrorView', 'ExecutionContext', 'false', 'FormatEnumerationLimit', 'HOME', 'Host', 'InformationPreference', 'input', 'IsCoreCLR', 'IsLinux', 'IsMacOS', 'IsWindows', 'MaximumHistoryCount', 'MyInvocation', 'NestedPromptLevel', 'null', 'OutputEncoding', 'PID', 'PROFILE', 'ProgressPreference', 'PSBoundParameters', 'PSCommandPath', 'PSCulture', 'PSDefaultParameterValues', 'PSEdition', 'PSEmailServer', 'PSHOME', 'PSScriptRoot', 'PSSessionApplicationName', 'PSSessionConfigurationName', 'PSSessionOption', 'PSStyle', 'PSUICulture', 'PSVersionTable', 'PWD', 'PwrSaveState', 'ShellId', 'StackTrace', 'true', 'VerbosePreference', 'WarningPreference', 'WhatIfPreference', 'ConsoleFileName', 'MaximumAliasCount', 'MaximumDriveCount', 'MaximumErrorCount', 'MaximumFunctionCount', 'MaximumVariableCount'
	foreach ($v in (Get-Variable -Scope Global)) {
		if ($v.name -notin $default) {
			Remove-Variable -Name $v.name -Scope Global -Force -ErrorAction SilentlyContinue
		}
	}
	foreach ($k in [Environment]::GetEnvironmentVariables([EnvironmentVariableTarget]::User).keys) {
		if ($k -notin 'temp', 'tmp', 'pwrhome') {
			Remove-Item "env:$k" -Force -ErrorAction SilentlyContinue
		}
	}
	Remove-Item 'env:PwrLoadedPackages' -Force -ErrorAction SilentlyContinue
}

function RestoreSessionState {
	foreach ($v in $PwrSaveState.vars) {
		Set-Variable -Name $v.name -Value $v.value -Scope Global -Force -ErrorAction SilentlyContinue
	}
	foreach ($e in $PwrSaveState.env) {
		Set-Item -Path "env:$($e.name)" -Value $e.value -Force -ErrorAction SilentlyContinue
	}
	Remove-Variable 'PwrSaveState' -Force -Scope Global -ErrorAction SilentlyContinue
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
				$pre = "$env:Path$(if ($env:Path) { ';' })"
			} else {
				$post = "$(if (-not $env:Path.StartsWith(';')) { ';' })$env:Path"
			}
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
	if ($digest -notin ($env:PwrLoadedPackages -split ';')) {
		$Pkg | ConfigurePackage
		$env:PwrLoadedPackages += "$(if ($env:PwrLoadedPackages) { ';' })$digest"
		WriteHost "Status: Session configured for $ref"
	} else {
		WriteHost "Status: Session is up to date for $ref"
	}
}

function ExecuteScript {
	param (
		[Parameter(Mandatory)]
		[scriptblock]$Script,
		[Parameter(Mandatory)]
		[Collections.Hashtable[]]$Pkgs
	)
	try {
		SaveSessionState
		ClearSessionState
		foreach ($pkg in $Pkgs) {
			$pkg.digest = $pkg | ResolvePackageDigest
			$ref = "$($Pkg.Package):$($Pkg.Tag | AsTagString)"
			if (-not $pkg.digest) {
				throw "no such package $ref"
			}
			$pkg | ConfigurePackage -AppendPath
		}
		$env:Path = "$(if ($env:Path) { "$env:Path;" })$env:SYSTEMROOT;$env:SYSTEMROOT\System32;$PSHOME"
		& $Script
	} finally {
		RestoreSessionState
	}
}
