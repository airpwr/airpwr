<#
.SYNOPSIS
	A package manager and environment to provide consistent tooling for software teams.
.DESCRIPTION
	`pwr` provides declarative development environments to teams when traditional isolation and virtualization technologies cannot be employed. Calling pwr shell configures a consistent, local shell with the needed tools used to build and run software. This empowers teams to maintain consistentency in their build process and track configuration in version control systems (CaC).
.LINK
	https://github.com/airpwr/airpwr
.PARAMETER Command
	list, ls		Displays all packages and their versions
	fetch			Downloads packages
	shell, sh		Configures the current shell for the given package list and starts a session
	exit			Exits the shell session and restores the pevious state
	help, h			Displays syntax and descriptive information for calling pwr
	version, v		Displays this verion of pwr
	remove, rm		Removes package data from the local machine
	update			Updates the pwr command to the latest version
.PARAMETER Fetch
	Forces the repository of packges to be synchronized from the upstream source
	Otherwise, the cached repository is used and updated if older than one day
.PARAMETER Packages
	A list of packages and their versions to be used in the fetch or shell command
	Must be in the form name[:version]
	  - When the version is omitted, the latest available is used
	  - Version must be in the form [Major[.Minor[.Patch]]] or 'latest'
	  - If the Minor or Patch is omitted, the latest available is used
	    (e.g. pkg:7 will select the latest version with Major version 7)
	When this parameter is omitted, packges are read from a file named 'pwr.json' in the current working directory
	  - The file must have the form { "packages": ["pkg:7", ... ] }
.PARAMETER Repositories
	A list of OCI compliant container repositories
	When this parameter is omitted and a file named 'pwr.json' exists the current working directory, repositories are read from that file
	  - The file must have the form { "repositories": ["example.com/v2/some/repo"] }
	  - The registry (e.g. 'example.com/v2/') may be omitted when the registry is DockerHub
	When this parameter is omitted and no file is present, a default repository is used

	In some cases, you will need to add authentication for custom repositories
	  - A file located at '%appdata%\pwr\auths.json' is read
	  - The file must have the form { "<repo url>": { "basic": "<base64>" }, ... }
#>
param (
	[Parameter(Position=0)]
	[string]$Command,
	[Parameter(Position=1)]
	[ValidatePattern('^((file:///.+)|([a-zA-Z0-9_-]+(:([0-9]+\.){0,2}[0-9]*)?$))')]
	[string[]]$Packages,
	[string[]]$Repositories,
	[switch]$Fetch
)

Class SemanticVersion : System.IComparable {

	[int]$Major = 0
	[int]$Minor = 0
	[int]$Patch = 0

	hidden init([string]$tag, [string]$pattern) {
		if ($tag -match $pattern) {
			$this.Major = if ($Matches.1) { $Matches.1 } else { 0 }
			$this.Minor = if ($Matches.2) { $Matches.2 } else { 0 }
			$this.Patch = if ($Matches.3) { $Matches.3 } else { 0 }
		}
	}

	SemanticVersion([string]$tag, [string]$pattern) {
		$this.init($tag, $pattern)
	}

	SemanticVersion([string]$version) {
		$this.init($version, '^([0-9]+)\.([0-9]+)\.([0-9]+)$')
	}

	SemanticVersion() { }

	[bool] LaterThan([object]$Obj) {
		return $this.CompareTo($obj) -lt 0
	}

	[int] CompareTo([object]$Obj) {
		if ($Obj -isnot [SemanticVersion]) {
			return 1
		} elseif (!($this.Major -eq $Obj.Major)) {
			return $Obj.Major - $this.Major
		} elseif (!($this.Minor -eq $Obj.Minor)) {
			return $Obj.Minor - $this.Minor
		} else {
			return $Obj.Patch - $this.Patch
		}
	}

	[string] ToString() {
		return "$($this.Major).$($this.Minor).$($this.Patch)"
	}

}

function global:Prompt {
	if ($env:InPwrShell) {
		Write-Host "$([char]27)[94mpwr:$([char]27)[0m" -NoNewline
		Write-Host " $($executionContext.SessionState.Path.CurrentLocation)$('>' * ($nestedPromptLevel + 1))" -NoNewline
		return " "
	} else {
		"PS $($executionContext.SessionState.Path.CurrentLocation)$('>' * ($nestedPromptLevel + 1)) "
	}
}

function Get-StringHash($s) {
	$stream = [IO.MemoryStream]::new([byte[]][char[]]$s)
	return (Get-FileHash -InputStream $stream).Hash.Substring(0, 12)
}

function ConvertTo-HashTable {
	param (
		[Parameter(ValueFromPipeline)][PSCustomObject]$Object
	)
	$Table = @{}
	$Object.PSObject.Properties | Foreach-Object {
		$V = $_.Value
		if ($V -is [array]) {
			$V = [System.Collections.ArrayList]$V
		} elseif ($V -is [PSCustomObject]) {
			$V = ($V | ConvertTo-HashTable)
		}
		$Table.($_.Name) = $V
	}
	return $Table
}

function Get-DockerToken($repo) {
	$resp = Invoke-WebRequest "https://auth.docker.io/token?service=registry.docker.io&scope=repository:$($repo.scope):pull"
	return ($resp.content | ConvertFrom-Json).token
}

function Get-ImageManifest($pkg) {
	$headers = @{"Accept" = "application/vnd.docker.distribution.manifest.v2+json"}
	if ($pkg.repo.Headers.Authorization) {
		$headers.Authorization = $pkg.repo.Headers.Authorization
	} elseif ($pkg.repo.IsDocker) {
		$headers.Authorization = "Bearer $(Get-DockerToken $pkg.repo)"
	}
	$resp = Invoke-WebRequest "$($pkg.repo.uri)/manifests/$($pkg.tag)" -Headers $headers -UseBasicParsing
	return [string]$resp | ConvertFrom-Json
}

function Invoke-PullImageLayer($out, $repo, $digest) {
	$tmp = "$env:temp/$($digest.Replace(':', '_')).tgz"
	$headers = @{}
	if ($repo.Headers.Authorization) {
		$headers.Authorization = $repo.Headers.Authorization
	} elseif ($repo.IsDocker) {
		$headers.Authorization = "Bearer $(Get-DockerToken $repo)"
	}
	Invoke-WebRequest "$($repo.uri)/blobs/$digest" -OutFile $tmp -Headers $headers
	tar -xzf $tmp -C $out --exclude 'Hives/*' --strip-components 1
	Remove-Item $tmp
}

function Get-RepoTags($repo) {
	$headers = @{}
	if ($repo.Headers.Authorization) {
		$headers.Authorization = $repo.Headers.Authorization
	} elseif ($repo.IsDocker) {
		$headers.Authorization = "Bearer $(Get-DockerToken $repo)"
	}
	$resp = Invoke-WebRequest "$($repo.uri)/tags/list" -Headers $headers -UseBasicParsing
	return [string]$resp | ConvertFrom-Json
}

function Resolve-PwrPackge($pkg) {
	if ($pkg.Local) {
		return $pkg.Path
	} else {
		return "$PwrPath\pkg\$($pkg.tag)"
	}
}

function Split-PwrPackage($pkg) {
	if ($pkg.StartsWith('file:///')) {
		return @{
			Name = $pkg
			Ref = $pkg
			Local = $true
			Path = (Resolve-Path $pkg.Substring(8)).Path
		}
	}
	$split = $pkg.Split(':')
	switch ($split.count) {
		2 {
			return @{
				Name = $split[0]
				Version = $split[1]
			}
		}
		Default {
			return @{
				Name = $pkg
				Version = 'latest'
			}
		}
	}
}

function Get-LatestVersion($pkgs, $matcher) {
	$latest = $null
	foreach ($v in $pkgs) {
		$ver = [SemanticVersion]::new($v, '([0-9]+)\.([0-9]+)\.([0-9]+)')
		if (($null -eq $latest) -or ($ver.CompareTo($latest) -lt 0)) {
			if ($matcher -and ($v -notmatch $matcher)) {
				continue
			}
			$latest = $ver
		}
	}
	if (-not $latest) {
		Write-Error "pwr: no package named $name$(if ($matcher) { " matching $matcher"} else { '' })"
	}
	return $latest.ToString()
}

function Assert-PwrPackage($pkg) {
	$p = Split-PwrPackage $pkg
	if ($p.Local) {
		return $p
	}
	$name = $p.name
	$version = $p.version
	foreach ($Repo in $PwrRepositories) {
		if (-not $Repo.Packages.$name) {
			continue
		} elseif ($version -eq 'latest') {
			$latest = Get-LatestVersion $Repo.Packages.$name
			$p.Tag = "$name-$latest"
			$p.Version = $latest
		} elseif ($version -match '^([0-9]+\.){2}[0-9]+$' -and ($version -in $Repo.Packages.$name)) {
			$p.Tag = "$name-$version"
		} elseif ($version -match '^[0-9]+(\.[0-9]+)?$') {
			$latest = Get-LatestVersion $Repo.Packages.$name $version
			$p.Tag = "$name-$latest"
			$p.Version = $latest
		}
		if ($p.Tag) {
			$p.Repo = $Repo
			$p.Ref = "$($p.name):$($p.version)"
			return $p
		}
	}
	Write-Error "pwr: no package for ${name}:$version"
}

function Get-PwrPackages {
	foreach ($Repo in $PwrRepositories) {
		$Cache = "$PwrPath\cache\$($repo.hash)"
		$exists = Test-Path $Cache
		if ($exists) {
			$LastWrite = [DateTime]::Parse((Get-Item $Cache).LastWriteTime)
			$OutOfDate = [DateTime]::Compare((Get-Date), $LastWrite + (New-TimeSpan -Days 1)) -gt 0
		}
		if (!$exists -or $OutOfDate -or $Fetch) {
			try {
				Write-Output "pwr: fetching tags from $($repo.uri)"
				$tagList = Get-RepoTags $Repo
				$pkgs = @{}
				$names = @{}
				foreach ($tag in $tagList.tags) {
					if ($tag -match '([^-]+)-(.+)') {
						$pkg = $Matches[1]
						$ver = $Matches[2]
						$names.$pkg = $null
						$pkgs.$pkg = @($pkgs.$pkg) + @([SemanticVersion]::new($ver)) | Sort-Object
					}
				}
				foreach ($name in $names.keys) {
					$pkgs.$name = $pkgs.$name | ForEach-Object { $_.ToString() }
				}
				mkdir (Split-Path $Cache -Parent) -Force | Out-Null
				[IO.File]::WriteAllText($Cache, (ConvertTo-Json $pkgs -Depth 50 -Compress))
			} catch {
				Write-Host -ForegroundColor Red "pwr: failed to fetch tags from $($repo.uri)"
				Write-Debug "    > $($Error[0])"
			}
		}
		$Repo.Packages = Get-Content $Cache -ErrorAction 'SilentlyContinue' | ConvertFrom-Json
	}

}

function Test-PwrPackage($pkg) {
	$PkgPath = Resolve-PwrPackge $pkg
	return Test-Path "$PkgPath\.pwr"
}

function Invoke-PwrPackagePull($pkg) {
	if (Test-PwrPackage $pkg) {
		Write-Output "pwr: $($pkg.ref) already exists"
	} else {
		Write-Host "pwr: fetching $($pkg.ref) ... " -NoNewline
		$manifest = Get-ImageManifest $pkg
		$PkgPath = Resolve-PwrPackge $pkg
		mkdir $PkgPath -Force | Out-Null
		foreach ($layer in $manifest.layers) {
			if ($layer.mediaType -eq "application/vnd.docker.image.rootfs.diff.tar.gzip") {
				Invoke-PullImageLayer $PkgPath $pkg.repo $layer.digest
			}
		}
		Write-Host 'done.'
	}
}

function Invoke-PwrPackageShell($pkg) {
	$PkgPath = Resolve-PwrPackge $pkg
	$vars = (Get-Content -Path "$PkgPath\.pwr").Replace('${.}', (Resolve-Path $PkgPath).Path.Replace('\', '\\')) | ConvertFrom-Json | ConvertTo-HashTable
	# Vars
	foreach ($k in $vars.var.keys) {
		Set-Variable -Name $k -Value $vars.var.$k -Scope 'global'
	}
	# Env
	foreach ($k in $vars.env.keys) {
		$prefix = ''
		if ($k -eq 'path') {
			$prefix += "${env:path};"
		}
		Set-Item "env:$k" "$prefix$($vars.env.$k)"
	}
}

function Assert-NonEmptyPwrPackages {
	if ($Packages.Count -eq 0) {
		if ($PwrConfig) {
			$script:Packages = $PwrConfig.Packages
		}
	}
	if ($Packages.Count -eq 0) {
		Write-Error 'pwr: no packages provided'
	}
}

function Get-PwrRepositories {
	$rs = if ($Repositories) { $Repositories } elseif ($PwrConfig.Repositories) { $PwrConfig.Repositories } else { ,'airpower/shipyard' }
	$repos = @()
	foreach ($repo in $rs) {
		$uri = $repo
		$headers = @{}
		if (-not $uri.Contains('/v2/')) {
			$uri = "index.docker.io/v2/$uri"
		}
		if (-not $uri.StartsWith('http')) {
			$uri = "https://$uri"
		}
		foreach ($auth in $PwrAuths.keys) {
			$authUri = if (-not $auth.StartsWith('http')) { "https://$auth" } else { $auth }
			if ($uri.StartsWith($authUri)) {
				if ($PwrAuths.$auth.basic) {
					$headers.Authorization = "Basic $($PwrAuths.$auth.basic)"
					break
				}
			}
		}
		$Repository = @{
			URI = $uri
			Scope = $uri.Substring($uri.IndexOf('/v2/') + 4)
			Hash = Get-StringHash $uri
		}
		if ($headers.count -gt 0) {
			$Repository.Headers = $headers
		}
		if ($uri.StartsWith('https://index.docker.io/v2/')) {
			$Repository.IsDocker = $true
		}
		$repos += ,$Repository
	}
	return $repos
}

function Save-PSSessionState {
	Write-Debug 'pwr: saving state'
	$vars = @()
	foreach ($v in (Get-Variable)) {
		$vars += ,@{
			Name = $v.Name
			Value = $v.Value
		}
	}
	$evars = @()
	foreach ($v in (Get-Item env:*)) {
		$evars += ,@{
			Name = $v.Name
			Value = $v.Value
		}
	}
	Set-Variable -Name PwrSaveState -Value @{
		Vars = $vars
		Env = $evars
	} -Scope 'global'
}

function Restore-PSSessionState {
	Write-Debug 'pwr: restoring state'
	$state = (Get-Variable 'PwrSaveState' -Scope 'global').Value
	foreach ($v in $state.vars) {
		Set-Variable -Name "$($v.Name)" -Value $v.Value -Scope 'global' -Force -ErrorAction 'SilentlyContinue'
	}
	Remove-Item -Path "env:*" -Force -ErrorAction 'SilentlyContinue'
	foreach ($e in $state.env) {
		Set-Item -Path "env:$($e.Name)" -Value $e.Value -Force -ErrorAction 'SilentlyContinue'
	}
	Set-Variable -Name PwrSaveState -Value $null -Scope 'Global'
}

function Clear-PSSessionState {
	Write-Debug 'pwr: clearing state'
	$DefaultVariableNames = '$', '?', '^', 'args', 'ConfirmPreference', 'ConsoleFileName', 'DebugPreference', 'Error', 'ErrorActionPreference', 'ErrorView', 'ExecutionContext', 'false', 'FormatEnumerationLimit', 'HOME', 'Host', 'InformationPreference', 'input', 'MaximumAliasCount', 'MaximumDriveCount', 'MaximumErrorCount', 'MaximumFunctionCount', 'MaximumHistoryCount', 'MaximumVariableCount', 'MyInvocation', 'NestedPromptLevel', 'null', 'OutputEncoding', 'PID', 'PROFILE', 'ProgressPreference', 'PSBoundParameters', 'PSCommandPath', 'PSCulture', 'PSDefaultParameterValues', 'PSEdition', 'PSEmailServer', 'PSHOME', 'PSScriptRoot', 'PSSessionApplicationName', 'PSSessionConfigurationName', 'PSSessionOption', 'PSUICulture', 'PSVersionTable', 'PWD', 'ShellId', 'StackTrace', 'true', 'VerbosePreference', 'WarningPreference', 'WhatIfPreference', 'PwrSaveState'
	$vars = Get-Variable -Scope 'global'
	foreach ($var in $vars) {
		if ($var.Name -notin $DefaultVariableNames) {
			Remove-Variable -Name "$($var.Name)" -Scope 'global' -Force -ErrorAction 'SilentlyContinue'
		}
	}
	foreach ($key in [Environment]::GetEnvironmentVariables([EnvironmentVariableTarget]::User).keys) {
		if (($key -ne 'tmp') -and ($key -ne 'temp')) {
			Clear-Item "env:$key" -Force -ErrorAction SilentlyContinue
		}
	}
}

$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'
$PwrVersion = '0.3.0'

switch ($Command) {
	{$_ -in 'v', 'version'} {
		Write-Host "pwr: version $PwrVersion"
		exit
	}
	{$_ -in '', 'h', 'help'} {
		Get-Help $MyInvocation.MyCommand.Path -detailed
		exit
	}
	'update' {
		Invoke-Expression (Invoke-WebRequest 'https://raw.githubusercontent.com/airpwr/airpwr/main/src/install.ps1')
		exit
	}
}

$PwrPath = "$env:appdata\pwr"
$PwrConfig = Get-Content 'pwr.json' -ErrorAction 'SilentlyContinue' | ConvertFrom-Json
$PwrAuths = Get-Content "$PwrPath\auths.json" -ErrorAction 'SilentlyContinue' | ConvertFrom-Json | ConvertTo-HashTable
$PwrRepositories = Get-PwrRepositories
Get-PwrPackages

switch ($Command) {
	'fetch' {
		Assert-NonEmptyPwrPackages
		foreach ($p in $Packages) {
			$pkg = Assert-PwrPackage $p
			Invoke-PwrPackagePull $pkg
		}
	}
	'exit' {
		if ($env:InPwrShell) {
			Restore-PSSessionState
			$env:InPwrShell = $null
			Write-Output 'pwr: shell session closed'
		} else {
			Write-Error "pwr: no shell session is in progress"
		}
	}
	{$_ -in 'sh', 'shell'} {
		if (-not $env:InPwrShell) {
			Save-PSSessionState
			$env:InPwrShell = $true
		} else {
			Write-Error "pwr: cannot start a new shell session while one is in progress; use `pwr exit` to end the existing session"
			break
		}
		Assert-NonEmptyPwrPackages
		Clear-PSSessionState
		$pwr = Split-Path $MyInvocation.MyCommand.Path -Parent
		$env:Path = "\windows;\windows\system32;\windows\system32\windowspowershell\v1.0\;$pwr"
		foreach ($p in $Packages) {
			$pkg = Assert-PwrPackage $p
			if (!(Test-PwrPackage $pkg)) {
				Invoke-PwrPackagePull $pkg
			}
			Invoke-PwrPackageShell $pkg
			Write-Output "$([char]27)[94mpwr:$([char]27)[0m using $($pkg.ref)"
		}
	}
	{$_ -in 'ls', 'list'} {
		foreach ($Repo in $PwrRepositories) {
			if (($Packages.count -eq 1) -and ($Packages[0] -match '[^:]+')) {
				$pkg = $Matches[0]
				Write-Output "pwr: $pkg[$($Repo.uri)]"
				if ($Repo.Packages.$pkg) {
					Write-Output $Repo.Packages.$pkg | Format-List
				} else {
					Write-Output "<none>"
				}
			} else {
				Write-Output "pwr: [$($Repo.uri)]"
				if ('' -ne $Repo.Packages) {
					Write-Output $Repo.Packages | Format-List
				} else {
					Write-Output "<none>"
				}
			}
		}
	}
	{$_ -in 'rm', 'remove'} {
		Assert-NonEmptyPwrPackages
		$name = [IO.Path]::GetRandomFileName()
		$empty = "$env:Temp\$name"
		mkdir $empty | Out-Null
		foreach ($p in $Packages) {
			$pkg = Assert-PwrPackage $p
			if ($pkg.Local) {
				Write-Error "pwr: tried to remove local package $($pkg.ref)"
			} elseif (Test-PwrPackage $pkg) {
				Write-Host "pwr: removing $($pkg.ref) ... " -NoNewline
				$path = Resolve-PwrPackge $pkg
				robocopy $empty $path /purge | Out-Null
				Remove-Item $path
				Write-Host 'done.'
			} else {
				Write-Output "pwr: $($pkg.ref) not found"
			}
		}
		Remove-Item $empty
	}
	Default {
		Write-Host -ForegroundColor Red "pwr: no such command '$Command'"
		Write-Host -ForegroundColor Red "     use 'pwr help' for a list of commands"
	}
}