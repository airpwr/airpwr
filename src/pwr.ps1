. $PSScriptRoot\package.ps1
. $PSScriptRoot\shell.ps1

$PwrHelp = @"

Usage: pwr COMMAND

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

# $PwrListHelp = @"

# Usage: pwr list [COMMAND]

# Lists packages

# Commands:
#   remote,		lists remote package
# "@

$PwrNoCommand = @"

To see avilable commands run
  pwr help
"@

$PwrRemoteNoCommand = @"

To see avilable commands run
  pwr remote help
"@

function Invoke-Airpower {
	param (
		[Parameter(ValueFromPipeline)]
		[object]$InputObject,
		[Parameter(ValueFromRemainingArguments, Position = 0)]
		[object[]]$Arguments
	)

	process {
		if ($InputObject) {
			$Arguments += $InputObject
		}
	}

	end {
		$ErrorActionPreference = 'Stop'
		if ($Arguments) {
			$first, $rest = $Arguments
			switch ($first) {
				{$_ -in 'v', 'version'} {
					(Get-Module -Name Airpower).Version
					return
				}
				'remote' {
					if ($Arguments.Count -eq 2) {
						switch ($Arguments[1]) {
							'list' {
								GetRemoteTags
								return
							}
							'help' {
								'todo'
								return
							}
							default {
								$PwrRemoteNoCommand
								return
							}
						}
					}
				}
				'list' {
					GetLocalPackages
					return
				}
				'load' {
					if (-not $rest) {
						$cfg = FindConfig
						. $cfg
						$rest = $PwrPackages
						if (-not $rest) {
							throw "no packages provided"
						}
					}
					foreach ($p in $rest) {
						$p | ResolvePackage | LoadPackage
					}
					return
				}
				'pull' {
					if (-not $rest) {
						$cfg = FindConfig
						. $cfg
						$rest = $PwrPackages
						if (-not $rest) {
							throw "no packages provided"
						}
					}
					foreach ($p in $rest) {
						$p | AsPackage | PullPackage
					}
					return
				}
				'prune' {
					PrunePackages
					return
				}
				{$_ -in 'remove', 'rm'} {
					foreach ($p in $rest) {
						$p | AsPackage | RemovePackage
					}
					return
				}
				'exec' {
					if ($rest.Count -eq 0) {
						throw "no scriptblock provided"
					} elseif ($rest.Count -eq 1) {
						$script = $rest
						$cfg = FindConfig
						. $cfg
						$pkgs = $PwrPackages
						if (-not $pkgs) {
							throw "no packages provided"
						}
					} else {
						$pkgs, $script = $rest[0..$($rest.Count - 2)], $rest[$($rest.Count - 1)]
					}
					if ($script -isnot [scriptblock]) {
						throw "'$script' is not a script"
					}
					$resolved = @()
					foreach ($p in $pkgs) {
						$resolved += $p | ResolvePackage
					}
					ExecuteScript -Script $script -Pkgs $resolved
					return
				}
				'run' {
					$cfg = FindConfig
					if (-not $cfg) {
						throw "no config file found"
					}
					$first, $rest = $rest
					if (-not $first) {
						throw "no script provided"
					}
					. $cfg
					$fn = Get-Item "function:Pwr$first"
					if ($rest) {
						& $fn @rest
					} else {
						& $fn
					}
					return
				}
				{$_ -in 'help', 'h'} {
					$PwrHelp
					return
				}
			}
		}
		throw $PwrNoCommand
	}
}

Set-Alias -Name 'pwr' -Value 'Invoke-Airpower' -Scope Global
