. $PSScriptRoot\package.ps1
. $PSScriptRoot\shell.ps1

<#
.SYNOPSIS
A package manager and environment to provide consistent tooling for software teams.

.DESCRIPTION
Airpower manages software packages using container technology and allows users to configure local PowerShell sessions to their need. Airpower seamlessly integrates common packages with a standardized project script to enable common build commands kept in source control for consistency.

.LINK
For detailed documentation and examples, visit https://github.com/airpwr/airpwr.
#>
function Invoke-Airpower {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[ValidateSet('version', 'v', 'remote', 'list', 'load', 'pull', 'exec', 'run', 'remove', 'rm', 'prune', 'update', 'help', 'h')]
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
			'update' {
				Invoke-AirpowerUpdate
			}
			{$_ -in 'remove', 'rm'} {
				if ($PSVersionTable.PSVersion.Major -le 5) {
					Invoke-AirpowerRemove @ArgumentList
				} else {
					Invoke-AirpowerRemove $ArgumentList
				}
			}
			'exec' {
				$fn = Get-Item 'function:Invoke-AirpowerExec'
				$params, $remaining = ResolveParameters $fn $ArgumentList
				if ((-not $params.ScriptBlock) -and ($null -ne $remaining) -and ($remaining[-1] -isnot [scriptblock])) {
					$params.Packages += $remaining | ForEach-Object { $_ }
					$remaining = @()
				}
				Invoke-AirpowerExec @params @remaining
			}
			'run' {
				if ($PSVersionTable.PSVersion.Major -le 5) {
					Invoke-AirpowerRun @ArgumentList
				} else {
					Invoke-AirpowerRun -FnName $ArgumentList[0] -ArgumentList $ArgumentList[1..$ArgumentList.Count]
				}
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
	LoadConfig
	[string[]]$AirpowerPackages
}

function ResolveParameters {
	param (
		[Parameter(Mandatory)]
		[System.Management.Automation.FunctionInfo]$Fn,
		[object[]]$ArgumentList
	)
	$params = @{}
	$remaining = [Collections.ArrayList]@()
	for ($i = 0; $i -lt $ArgumentList.Count; $i++) {
		if ($Fn.parameters.keys -and ($ArgumentList[$i] -match '^-([^:]+)(?::(.*))?$') -and ($Matches[1] -in $Fn.parameters.keys)) {
			$name = $Matches[1]
			$value = $Matches[2]
			if ($value) {
				$params.$name = $value
			} else {
				if ($Fn.parameters.$name.SwitchParameter -and $null -eq $value) {
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
	UpdatePackages -Auto $Packages
	TryEachPackage $Packages { $Input | ResolvePackage | LoadPackage } -ActionDescription 'load'
}

function Invoke-AirpowerRemove {
	[CmdletBinding()]
	param (
		[string[]]$Packages
	)
	TryEachPackage $Packages { $Input | AsPackage | RemovePackage } -ActionDescription 'remove'
}

function Invoke-AirpowerUpdate {
	[CmdletBinding()]
	param ()
	UpdatePackages
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
	TryEachPackage $Packages { $Input | AsPackage | PullPackage | Out-Null } -ActionDescription 'pull'
}

function Invoke-AirpowerRun {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$FnName,
		[Parameter(ValueFromRemainingArguments)]
		[object[]]$ArgumentList
	)
	LoadConfig
	$fn = Get-Item "function:AirpowerRun$FnName"
	$params, $remaining = ResolveParameters $fn $ArgumentList
	$script = { & $fn @params @remaining }
	if ($AirpowerPackages) {
		Invoke-AirpowerExec -Packages $AirpowerPackages -ScriptBlock $script
	} else {
		& $script
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
	UpdatePackages -Auto $Packages
	$resolved = TryEachPackage $Packages { $Input | ResolvePackage } -ActionDescription 'resolve'
	ExecuteScript -ScriptBlock $ScriptBlock -Pkgs $resolved
}

function Invoke-AirpowerRemote {
	[CmdletBinding()]
	param (
		[ValidateSet('', 'list', 'set')]
		[string]$Command,
		[ValidateScript({ $Command -eq 'set' })]
		[string]$Remote
	)
	switch ($Command) {
		'' {
			GetAirpowerRemote
		}
		'list' {
			GetRemoteTags
		}
		'set' {
			SetAirpowerRemote $Remote
		}
	}
}

function Invoke-AirpowerHelp {
@"

Usage: airpower COMMAND

Commands:
  version        Outputs the version of the module
  list           Outputs a list of installed packages
  remote list    Outputs an object of remote packages and versions
  pull           Downloads packages
  load           Loads packages into the PowerShell session
  exec           Runs a user-defined scriptblock in a managed PowerShell session
  run            Runs a user-defined scriptblock provided in a project file
  update         Updates all tagged packages
  prune          Deletes unreferenced packages
  remove         Untags and deletes packages
  help           Outputs usage for this command

For detailed documentation and examples, visit https://github.com/airpwr/airpwr.

"@
}

function CheckForUpdates {
	try {
		$params = @{
			Url = "https://www.powershellgallery.com/packages/airpower"
			Method = 'HEAD'
		}
		$resp = HttpRequest @params | HttpSend -NoRedirect
		if ($resp.Headers.Location) {
			$remote = [Version]::new($resp.Headers.Location.OriginalString.Substring('/packages/airpower/'.Length))
			$local = [Version]::new((Import-PowerShellDataFile -Path "$PSScriptRoot\Airpower.psd1").ModuleVersion)
			if ($remote -gt $local) {
				WriteHost "$([char]27)[92mA new version of Airpower is available! [v$remote]$([char]27)[0m"
				WriteHost "$([char]27)[92mUse command ``Update-Module Airpower`` for the latest version$([char]27)[0m"
			}
		}
	} catch {
		Write-Debug "failed to check for updates: $_"
	}
}

Set-Alias -Name 'airpower' -Value 'Invoke-Airpower' -Scope Global
Set-Alias -Name 'air' -Value 'Invoke-Airpower' -Scope Global
Set-Alias -Name 'pwr' -Value 'Invoke-Airpower' -Scope Global

& {
	if ('Airpower.psm1' -eq (Split-Path $MyInvocation.ScriptName -Leaf)) {
		# Invoked as a module
		CheckForUpdates
		PrunePackages -Auto
	}
}
