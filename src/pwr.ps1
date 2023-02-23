. $PSScriptRoot\package.ps1
. $PSScriptRoot\shell.ps1

function Invoke-Airpower {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[ValidateSet('version', 'v', 'remote', 'list', 'load', 'pull', 'exec', 'run', 'remove', 'rm', 'prune', 'help', 'h')]
		[string]$Command,
		[Parameter(ValueFromRemainingArguments)]
		[object[]]$ArgumentList
	)
	try {
		switch ($Command) {
			{$_ -in 'v', 'version'} {
				Invoke-AirpowerVersion
			}
			'remote' {
				Invoke-AirpowerRemote @ArgumentList
			}
			'list' {
				Invoke-AirpowerList
			}
			'load' {
				if ($PSVersionTable.PSVersion.Major -le 5) {
					Invoke-AirpowerLoad @ArgumentList
				} else {
					Invoke-AirpowerLoad $ArgumentList
				}
			}
			'pull' {
				if ($PSVersionTable.PSVersion.Major -le 5) {
					Invoke-AirpowerPull @ArgumentList
				} else {
					Invoke-AirpowerPull $ArgumentList
				}
			}
			'prune' {
				Invoke-AirpowerPrune
			}
			{$_ -in 'remove', 'rm'} {
				if ($PSVersionTable.PSVersion.Major -le 5) {
					Invoke-AirpowerRemove @ArgumentList
				} else {
					Invoke-AirpowerRemove $ArgumentList
				}
			}
			'exec' {
				$params, $remaining = ResolveParameters 'Invoke-AirpowerExec' $ArgumentList
				Invoke-AirpowerExec @params @remaining
			}
			'run' {
				Invoke-AirpowerRun @ArgumentList
			}
			{$_ -in 'help', 'h'} {
				Invoke-AirpowerHelp
			}
		}
	} catch {
		Write-Error $_
	}
}

function GetConfigPackages {
	$cfg = FindConfig
	if ($cfg) {
		. $cfg
	}
	[string[]]$AirpowerPackages
}

function ResolveParameters {
	param (
		[Parameter(Mandatory)]
		[string]$FnName,
		[object[]]$ArgumentList
	)
	$fn = Get-Item "function:$FnName"
	$params = @{}
	$remaining = [Collections.ArrayList]@()
	for ($i = 0; $i -lt $ArgumentList.Count; $i++) {
		if ($fn.parameters.keys -and ($ArgumentList[$i] -match '^-([^:]+)(?::(.*))?$') -and ($Matches[1] -in $fn.parameters.keys)) {
			$name = $Matches[1]
			$value = $Matches[2]
			if ($value) {
				$params.$name = $value
			} else {
				if ($fn.parameters.$name.SwitchParameter -and $null -eq $value) {
					$params.$name = $true
				} else {
					$params.$name = $ArgumentList[$i+1]
					$i++
				}
			}
		} else {
			[void]$remaining.Add($ArgumentList[$i])
		}
	}
	return $params, $remaining
}

function Invoke-AirpowerVersion {
	[CmdletBinding()]
	param ()
	(Get-Module -Name Airpower).Version
}

function Invoke-AirpowerList {
	[CmdletBinding()]
	param ()
	GetLocalPackages
}

function Invoke-AirpowerLoad {
	[CmdletBinding()]
	param (
		[string[]]$Packages
	)
	if (-not $Packages) {
		$Packages = GetConfigPackages
	}
	if (-not $Packages) {
		Write-Error 'no packages provided'
	}
	foreach ($p in $Packages) {
		$p | ResolvePackage | LoadPackage
	}
}

function Invoke-AirpowerRemove {
	[CmdletBinding()]
	param (
		[string[]]$Packages
	)
	foreach ($p in $Packages) {
		$p | AsPackage | RemovePackage
	}
}

function Invoke-AirpowerPrune {
	[CmdletBinding()]
	param ()
	PrunePackages
}

function Invoke-AirpowerPull {
	[CmdletBinding()]
	param (
		[string[]]$Packages
	)
	if (-not $Packages) {
		$Packages = GetConfigPackages
	}
	if (-not $Packages) {
		Write-Error "no packages provided"
	}
	foreach ($p in $Packages) {
		$p | AsPackage | PullPackage
	}
}

function Invoke-AirpowerRun {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$FnName,
		[Parameter(ValueFromRemainingArguments)]
		[object[]]$ArgumentList
	)
	$cfg = FindConfig
	if ($cfg) {
		. $cfg
	}
	$fn = Get-Item "function:Airpower$FnName"
	if ($fn) {
		$params, $remaining = ResolveParameters "Airpower$FnName" $ArgumentList
		$script = { & $fn @params @remaining }
		if ($AirpowerPackages) {
			Invoke-AirpowerExec -Packages $AirpowerPackages -ScriptBlock $script
		} else {
			& $script
		}
	}
}

function Invoke-AirpowerExec {
	[CmdletBinding()]
	param (
		[string[]]$Packages,
		[scriptblock]$ScriptBlock = { $Host.EnterNestedPrompt() }
	)
	if (-not $Packages) {
		$Packages = GetConfigPackages
	}
	if (-not $Packages) {
		Write-Error "no packages provided"
	}
	$resolved = @()
	foreach ($p in $Packages) {
		$resolved += $p | ResolvePackage
	}
	ExecuteScript -ScriptBlock $ScriptBlock -Pkgs $resolved
}

function Invoke-AirpowerRemote {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[ValidateSet('list')]
		[string]$Command
	)
	switch ($Command) {
		'list' {
			GetRemoteTags
		}
	}
}

function Invoke-AirpowerHelp {
@"

Usage: airpower COMMAND

A package manager and environment to provide consistent tooling for software teams

Commands:
	version, v      Outputs the version of the module
	list            Outputs a list of installed packages
	remote list     Outputs an object of remote packages and versions
	pull            Downlaods packages
	load            Loads packages into the PowerShell session
	exec            Runs a user-defined scriptblock in a managed PowerShell session state
	run             Runs a user-defined scriptblock provided in a project file
	prune           Deletes unreferenced packages
	remove, rm      Untags and deletes packages
"@
}

Set-Alias -Name 'airpower' -Value 'Invoke-Airpower' -Scope Global
Set-Alias -Name 'air' -Value 'Invoke-Airpower' -Scope Global
Set-Alias -Name 'pwr' -Value 'Invoke-Airpower' -Scope Global

& {
	if ('Airpower.psm1' -eq (Split-Path $MyInvocation.ScriptName -Leaf)) {
		# Invoked as a module
		$local = [Version]::new((Import-PowerShellDataFile -Path "$PSScriptRoot\Airpower.psd1").ModuleVersion)
		$remote = [Version]::new((Get-Package -Name Airpower).Version)
		if ($remote -gt $local) {
			WriteHost "$([char]27)[92mA new version of Airpower is available! [v$remote]$([char]27)[0m"
		}
		PrunePackages -Auto
	}
}
