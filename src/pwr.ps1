<#
.SYNOPSIS
	A package manager and environment to provide consistent tooling for software teams.
.DESCRIPTION
	`pwr` provides declarative development environments to teams when traditional isolation and virtualization technologies cannot be employed. Calling `pwr shell` configures a consistent, local shell with the needed tools used to build and run software. This empowers teams to maintain consistentency in their build process and track configuration in version control systems (CaC).
.LINK
	https://github.com/airpwr/airpwr
.PARAMETER Command
	list, ls		Displays all packages and their versions
	ls-config		Displays all configurations for a package
	fetch			Downloads packages
	shell, sh		Configures the terminal with the listed packages and starts a session
	exit			Ends the session and restores the previous terminal state
	load			Loads packages into the terminal transparently to shell sessions
	help, h			Displays syntax and descriptive information for calling pwr
	version, v		Displays this verion of pwr
	remove, rm		Removes package data from the local machine
	update			Updates the pwr command to the latest version
.PARAMETER Packages
	A list of packages and their versions to be used in the fetch or shell command
	Must be in the form name[:version][:configuration]
	  - When the version is omitted, the latest available is used
	  - Version must be in the form [Major[.Minor[.Patch]]] or 'latest'
	  - If the Minor or Patch is omitted, the latest available is used
		(e.g. pkg:7 will select the latest version with Major version 7)
	  - When the configuration is omitted, the default used
	When this parameter is omitted, packages are read from a file named 'pwr.json' in the current or any parent directories
	  - The file must have the form { "packages": ["pkg:7", ... ] }
.PARAMETER Repositories
	A list of OCI compliant container repositories
	When this parameter is omitted and a file named 'pwr.json' exists in the current or any parent directories, repositories are read from that file
	  - The file must have the form { "repositories": ["example.com/v2/some/repo"] }
	  - The registry (e.g. 'example.com/v2/') may be omitted when the registry is DockerHub
	When this parameter is omitted and no file is present, a default repository is used

	In some cases, you will need to add authentication for custom repositories
	  - A file located at '%appdata%\pwr\auths.json' is read
	  - The file must have the form { "<repo url>": { "basic": "<base64>" }, ... }
.PARAMETER Fetch
	Forces the repository of packages to be synchronized from the upstream source
	Otherwise, the cached repository is used and updated if older than one day
.PARAMETER Offline
	Prevents attempts to request a web resource
.PARAMETER Quiet
	Suppresses all output to stdout
.PARAMETER Silent
	Suppresses all output to stdout and stderr
.PARAMETER AssertMinimum
	Writes an error if the provided semantic version (a.b.c) is not met by this scripts version
	Must be called with the `version` command
.PARAMETER Override
	Overrides 'pwr.json' package versions with the versions provided by the `Packages` parameter
	The package must be declared in the configuration file
	The package must not be expressed by a file URI
.PARAMETER DaysOld
	Use with the `remove` command to delete packages that have not been used within the specified period of days
	When this parameter is used, `Packages` must be empty
.PARAMETER Installed
	Use with the `list` command to enumerate the packages installed on the local machine
.PARAMETER WhatIf
	Use with the `remove` command to show the dry-run of packages to remove
.PARAMETER Run
	Executes the user-defined script inside a shell session
	The script is declared like `{ ..., "scripts": { "name": "something to run" } }` in 'pwr.json'
	The command string is interpreted by the String.Format method, so characters such as '{' and '}' need to be escaped by '{{' and '}}' respectively
	Additional arguments may also be provided to the script, referenced in the script as {1}, {2}, etc.
	For instance, a parameterized script is declared like `{ ..., "scripts": { "name": "something to run --arg={1}" } }` in 'pwr.json'
#>
[CmdletBinding(SupportsShouldProcess)]
param (
	[Parameter(Position = 0)]
	[string]$Command,
	[Parameter(Position = 1)]
	[ValidatePattern('^((file:///.+)|([a-zA-Z0-9_-]+(:((([0-9]+\.){0,2}[0-9]+)|latest|(?=:))(:([a-zA-Z0-9_-]+))?)?))$')]
	[string[]]$Packages,
	[string[]]$Repositories,
	[switch]$Fetch,
	[switch]$Installed,
	[ValidatePattern('^([0-9]+)\.([0-9]+)\.([0-9]+)$')]
	[string]$AssertMinimum,
	[ValidatePattern('^[1-9][0-9]*$')]
	[int]$DaysOld,
	[switch]$Offline,
	[switch]$Quiet,
	[switch]$Silent,
	[switch]$Override,
	[string[]]$Run
)

Class SemanticVersion : System.IComparable {

	[int]$Major = 0
	[int]$Minor = 0
	[int]$Patch = 0
	[int]$Build = 0

	hidden init([string]$Tag, [string]$Pattern) {
		if ($Tag -match $Pattern) {
			$This.Major = if ($Matches[1]) { $Matches[1] } else { 0 }
			$This.Minor = if ($Matches[2]) { $Matches[2] } else { 0 }
			$This.Patch = if ($Matches[3]) { $Matches[3] } else { 0 }
			$This.Build = if ($Matches[4]) { $Matches[4].Substring(1) } else { 0 }
		}
	}

	SemanticVersion([string]$Tag, [string]$Pattern) {
		$This.init($Tag, $Pattern)
	}

	SemanticVersion([string]$Version) {
		$This.init($Version, '^([0-9]+)\.([0-9]+)\.([0-9]+)(\+[0-9]+)?$')
	}

	SemanticVersion() { }

	[bool] LaterThan([object]$Obj) {
		return $This.CompareTo($Obj) -gt 0
	}

	[int] CompareTo([object]$Obj) {
		if ($Obj -isnot $This.GetType()) {
			throw "cannot compare types $($Obj.GetType()) and $($This.GetType())"
		} elseif ($This.Major -ne $Obj.Major) {
			return $This.Major - $Obj.Major
		} elseif ($This.Minor -ne $Obj.Minor) {
			return $This.Minor - $Obj.Minor
		} elseif ($This.Patch -ne $Obj.Patch) {
			return $This.Patch - $Obj.Patch
		} else {
			return $This.Build - $Obj.Build
		}
	}

	[string] ToString() {
		return "$($This.Major).$($This.Minor).$($This.Patch)$(if ($This.Build) {"+$($This.Build)"})"
	}

}

function global:Prompt {
	if ($env:InPwrShell) {
		Write-Host -ForegroundColor Blue -NoNewline 'pwr:'
		Write-Host " $($ExecutionContext.SessionState.Path.CurrentLocation)$('>' * ($NestedPromptLevel + 1))" -NoNewline
		return ' '
	} else {
		"PS $($ExecutionContext.SessionState.Path.CurrentLocation)$('>' * ($NestedPromptLevel + 1)) "
	}
}

function Write-PwrOutput {
	if (-not $Quiet -and -not $Silent) {
		Write-Output @Args
	}
}

function Write-PwrHost {
	if (-not $Quiet -and -not $Silent) {
		Write-Host @Args
	}
}

function Write-PwrFatal($Message) {
	if (-not $Silent) {
		Write-Host -ForegroundColor Red $Message
	}
	exit 1
}

function Write-PwrThrow($Message) {
	if (-not $Silent) {
		Write-Host -ForegroundColor Red $Message
	}
	throw $Message
}

function Write-PwrWarning($Message) {
	if (-not $Silent) {
		Write-Host -ForegroundColor Yellow $Message
	}
}

function Invoke-PwrWebRequest($Uri, $Headers, $OutFile, [switch]$UseBasicParsing) {
	if ($Offline) {
		Write-PwrThrow 'pwr: cannot web request while running offline'
	} elseif ($PwrWebPath -and (Test-Path -Path $PwrWebPath -PathType Leaf)) {
		Write-Debug "pwr: using http client $PwrWebPath"
		$Expr = "$PwrWebPath -s -L --url '$Uri'"
		foreach ($K in $Headers.Keys) {
			$Expr += " --header '${K}: $($Headers.$K)'"
		}
		if ($OutFile) {
			$Expr += " --output '$OutFile'"
		}
		return Invoke-Expression $Expr
	}
	return Invoke-WebRequest @PSBoundParameters
}

function Get-StringHash($S) {
	$Stream = [IO.MemoryStream]::new([byte[]][char[]]$S)
	return (Get-FileHash -InputStream $Stream).Hash.Substring(0, 12)
}

function ConvertTo-HashTable {
	param (
		[Parameter(ValueFromPipeline)][PSCustomObject]$Object
	)
	$Table = @{}
	$Object.PSObject.Properties | ForEach-Object {
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

function Get-DockerToken($Repo) {
	$Resp = Invoke-PwrWebRequest "https://auth.docker.io/token?service=registry.docker.io&scope=repository:$($Repo.scope):pull"
	return ($Resp | ConvertFrom-Json).token
}

function Get-ImageManifest($Pkg) {
	$Headers = @{'Accept' = 'application/vnd.docker.distribution.manifest.v2+json'}
	if ($Pkg.repo.Headers.Authorization) {
		$Headers.Authorization = $Pkg.repo.Headers.Authorization
	} elseif ($Pkg.repo.IsDocker) {
		$Headers.Authorization = "Bearer $(Get-DockerToken $Pkg.repo)"
	}
	$Resp = Invoke-PwrWebRequest "$($Pkg.repo.uri)/manifests/$($Pkg.tag)" -Headers $Headers -UseBasicParsing
	return [string]$Resp | ConvertFrom-Json
}

function Invoke-PullImageLayer($Out, $Repo, $Digest) {
	$Tmp = "$env:Temp/$($Digest.Replace(':', '_')).tgz"
	if (-not ((Test-Path -Path $Tmp -PathType Leaf) -and (Get-FileHash -Path $Tmp -Algorithm SHA256).Hash -eq $Digest.Replace('sha256:', ''))) {
		$Headers = @{}
		if ($Repo.Headers.Authorization) {
			$Headers.Authorization = $Repo.Headers.Authorization
		} elseif ($Repo.IsDocker) {
			$Headers.Authorization = "Bearer $(Get-DockerToken $Repo)"
		}
		Invoke-PwrWebRequest "$($Repo.uri)/blobs/$Digest" -OutFile $Tmp -Headers $Headers
	} else {
		Write-PwrHost 'using cache ... ' -NoNewline
	}
	& 'C:\WINDOWS\system32\tar.exe' -xzf $Tmp -C $Out --exclude 'Hives/*' --strip-components 1
	Remove-Item $Tmp
}

function Get-RepoTags($Repo) {
	$Headers = @{}
	if ($Repo.Headers.Authorization) {
		$Headers.Authorization = $Repo.Headers.Authorization
	} elseif ($Repo.IsDocker) {
		$Headers.Authorization = "Bearer $(Get-DockerToken $Repo)"
	}
	$Resp = Invoke-PwrWebRequest "$($Repo.uri)/tags/list" -Headers $Headers -UseBasicParsing
	return [string]$Resp | ConvertFrom-Json
}

function Resolve-PwrPackge($Pkg) {
	if ($Pkg.Local) {
		return $Pkg.Path
	} else {
		return "$PwrPkgPath\$($Pkg.tag)"
	}
}

function Split-PwrPackage($Pkg) {
	if ($Pkg.StartsWith('file:///')) {
		$Split = $Pkg.Split('<')
		$Uri = $Split[0].trim()
		return @{
			Name = $Uri
			Ref = $Uri
			Local = $true
			Path = (Resolve-Path $Uri.Substring(8)).Path
			Config = if ($Split[1]) { $Split[1].trim() } else { 'default' }
		}
	}
	$Split = $Pkg.Split(':')
	$Props = @{
		Name = $Split[0]
		Version = 'latest'
		Config = 'default'
	}
	if ($Split.count -ge 2 -and ($Split[1] -ne '')) {
		$Props.Version = $Split[1]
	}
	if ($Split.count -ge 3 -and ($Split[2] -ne '')) {
		$Props.Config = $Split[2]
	}
	return $Props;
}

function Get-LatestVersion($Pkgs, $Matcher) {
	$Latest = $null
	foreach ($V in $Pkgs) {
		$Ver = [SemanticVersion]::new($V, '([0-9]+)\.([0-9]+)\.([0-9]+)')
		if (($null -eq $Latest) -or ($Ver.LaterThan($Latest))) {
			if ($Matcher -and ($V -notmatch $Matcher)) {
				continue
			}
			$Latest = $Ver
		}
	}
	if (-not $Latest) {
		Write-PwrFatal "pwr: no package named $Name$(if ($Matcher) { " matching $Matcher"} else { '' })"
	}
	return $Latest.ToString()
}

function Assert-PwrPackage($Pkg) {
	$P = Split-PwrPackage $Pkg
	if ($P.Local) {
		return $P
	}
	$Name = $P.name
	$Version = $P.version
	foreach ($Repo in $PwrRepositories) {
		if (-not $Repo.Packages.$Name) {
			continue
		} elseif ($Version -eq 'latest') {
			$Latest = Get-LatestVersion $Repo.Packages.$Name
			$P.Tag = "$Name-$Latest"
			$P.Version = $Latest
		} elseif ($Version -match '^([0-9]+\.){2}[0-9]+$' -and ($Version -in $Repo.Packages.$Name)) {
			$P.Tag = "$Name-$Version"
		} elseif ($Version -match '^[0-9]+(\.[0-9]+)?$') {
			$Latest = Get-LatestVersion $Repo.Packages.$Name $Version
			$P.Tag = "$Name-$Latest"
			$P.Version = $Latest
		}
		if ($P.Tag) {
			$P.Repo = $Repo
			$P.Ref = "$($P.name):$($P.version)"
			return $P
		}
	}
	if (-not $Offline -and -not $Fetch) {
		$script:Fetch = $true
		Get-PwrPackages
		return Assert-PwrPackage $Pkg
	}
	Write-PwrFatal "pwr: no package for ${Name}:$Version"
}

function Compare-PwrTags {
	$Cache = "$PwrPath\cache\PwrTags"
	$CacheExists = Test-Path $Cache
	if ($CacheExists) {
		$LastWrite = [DateTime]::Parse((Get-Item $Cache).LastWriteTime)
		$OutOfDate = [DateTime]::Compare((Get-Date), $LastWrite + (New-TimeSpan -Days 1)) -gt 0
	}
	if ((-not $Offline) -and (-not $CacheExists -or $OutOfDate -or $Fetch)) {
		try {
			$Req = Invoke-PwrWebRequest -Uri 'https://api.github.com/repos/airpwr/airpwr/tags' -UseBasicParsing
			mkdir (Split-Path $Cache -Parent) -Force | Out-Null
			[IO.File]::WriteAllText($Cache, $Req)
		} catch { }
	}
	$Tags = Get-Content $Cache -ErrorAction 'SilentlyContinue' | ConvertFrom-Json
	$Latest = [SemanticVersion]::new()
	foreach ($Tag in $Tags) {
		$Ver = [SemanticVersion]::new($Tag.name.Substring(1))
		if ($Ver.LaterThan($Latest)) {
			$Latest = $Ver
		}
	}
	if ($Latest.LaterThan([SemanticVersion]::new($env:PwrVersion))) {
		Write-PwrHost -ForegroundColor Green "pwr: a new version ($Latest) is available!"
		Write-PwrHost -ForegroundColor Green "pwr: use command 'update' to install"
	}
}

function Get-PwrPackages {
	foreach ($Repo in $PwrRepositories) {
		$Cache = "$PwrPath\cache\$($Repo.hash)"
		$CacheExists = Test-Path $Cache
		if ($CacheExists) {
			$LastWrite = [DateTime]::Parse((Get-Item $Cache).LastWriteTime)
			$OutOfDate = [DateTime]::Compare((Get-Date), $LastWrite + (New-TimeSpan -Days 1)) -gt 0
		}
		if ($Offline) {
			Write-PwrOutput 'pwr: skipping fetch tags while running offline'
		} elseif (-not $CacheExists -or $OutOfDate -or $Fetch) {
			try {
				Write-PwrOutput "pwr: fetching tags from $($Repo.uri)"
				$TagList = Get-RepoTags $Repo
				$Pkgs = @{}
				$Names = @{}
				foreach ($Tag in $TagList.tags) {
					if ($Tag -match '(.+)-([0-9].+)') {
						$Pkg = $Matches[1]
						$Ver = $Matches[2]
						$Names.$Pkg = $null
						$Pkgs.$Pkg = @($Pkgs.$Pkg) + @([SemanticVersion]::new($Ver)) | Sort-Object
					}
				}
				foreach ($Name in $Names.keys) {
					$Pkgs.$Name = $Pkgs.$Name | ForEach-Object { $_.ToString() }
				}
				mkdir (Split-Path $Cache -Parent) -Force | Out-Null
				[IO.File]::WriteAllText($Cache, (ConvertTo-Json $Pkgs -Depth 50 -Compress))
			} catch {
				Write-PwrHost -ForegroundColor Red "pwr: failed to fetch tags from $($Repo.uri)"
				Write-Debug "    > $($Error[0])"
			}
		}
		$Repo.Packages = Get-Content $Cache -ErrorAction 'SilentlyContinue' | ConvertFrom-Json
	}

}

function Test-PwrPackage($Pkg) {
	$PkgPath = Resolve-PwrPackge $Pkg
	return Test-Path "$PkgPath\.pwr"
}

function Invoke-PwrPackagePull($Pkg) {
	if (Test-PwrPackage $Pkg) {
		Write-PwrOutput "pwr: $($Pkg.ref) already exists"
	} elseif ($Offline) {
		Write-PwrFatal "pwr: cannot fetch $($Pkg.ref) while running offline"
	} else {
		Write-PwrHost "pwr: fetching $($Pkg.ref) ... " -NoNewline
		$Manifest = Get-ImageManifest $Pkg
		$PkgPath = Resolve-PwrPackge $Pkg
		mkdir $PkgPath -Force | Out-Null
		foreach ($Layer in $Manifest.layers) {
			if ($Layer.mediaType -eq 'application/vnd.docker.image.rootfs.diff.tar.gzip') {
				Invoke-PullImageLayer $PkgPath $Pkg.repo $Layer.digest
			}
		}
		Write-PwrHost 'done.'
	}
}

function Invoke-PwrPackageShell($Pkg) {
	$PkgPath = Resolve-PwrPackge $Pkg
	if ($Offline -and -not (Test-PwrPackage $Pkg)) {
		Write-PwrThrow "pwr: cannot resolve package $($Pkg.ref) while running offline"
	}
	$Vars = (Get-Content -Path "$PkgPath\.pwr").Replace('${.}', (Resolve-Path $PkgPath).Path.Replace('\', '\\')) | ConvertFrom-Json | ConvertTo-HashTable
	if ($Pkg.config -eq 'default') {
		$PkgVar = $Vars
	} else {
		if (-not $Vars."$($Pkg.config)") {
			Write-PwrThrow "pwr: no such configuration '$($Pkg.config)' for $($Pkg.ref)"
		}
		$PkgVar = $Vars."$($Pkg.config)"
	}
	Format-Table $PkgEnv
	# Vars
	foreach ($K in $PkgVar.var.keys) {
		Set-Variable -Name $K -Value $PkgVar.var.$K -Scope 'global'
	}
	# Env
	foreach ($K in $PkgVar.env.keys) {
		$Prefix = ''
		if ($K -eq 'path') {
			$Prefix += "${env:Path};"
		}
		Set-Item "env:$K" "$Prefix$($PkgVar.env.$K)"
	}
	$Item = Get-ChildItem -Path "$PkgPath\.pwr"
	$Item.LastAccessTime = (Get-Date)
}

function Assert-NonEmptyPwrPackages {
	if ($Packages.Count -gt 0) {
		return
	} elseif ($PwrConfig.Packages.Count -gt 0) {
		Write-Debug "pwr: using config at $PwrConfigPath"
		$script:Packages = $PwrConfig.Packages
	} elseif ($PwrConfig) {
		Write-PwrFatal "pwr: no packages declared in $PwrConfigPath"
	} else {
		Write-PwrFatal 'pwr: no packages provided'
	}
}

function Get-PwrRepositories {
	$Rs = if ($Repositories) { $Repositories } elseif ($PwrConfig.Repositories) { $PwrConfig.Repositories } else { , 'airpower/shipyard' }
	$Repos = @()
	foreach ($Repo in $Rs) {
		$Uri = $Repo
		$Headers = @{}
		if (-not $Uri.Contains('/v2/')) {
			$Uri = "index.docker.io/v2/$Uri"
		}
		if (-not $Uri.StartsWith('http')) {
			$Uri = "https://$Uri"
		}
		foreach ($Auth in $PwrAuths.keys) {
			$AuthUri = if (-not $Auth.StartsWith('http')) { "https://$Auth" } else { $Auth }
			if ($Uri.StartsWith($AuthUri)) {
				if ($PwrAuths.$Auth.basic) {
					$Headers.Authorization = "Basic $($PwrAuths.$Auth.basic)"
					break
				}
			}
		}
		$Repository = @{
			URI = $Uri
			Scope = $Uri.Substring($Uri.IndexOf('/v2/') + 4)
			Hash = Get-StringHash $Uri
		}
		if ($Headers.count -gt 0) {
			$Repository.Headers = $Headers
		}
		if ($Uri.StartsWith('https://index.docker.io/v2/')) {
			$Repository.IsDocker = $true
		}
		$Repos += , $Repository
	}
	return $Repos
}

function Save-PSSessionState {
	Write-Debug 'pwr: saving state'
	$Vars = @()
	foreach ($V in (Get-Variable)) {
		$Vars += , @{
			Name = $V.Name
			Value = $V.Value
		}
	}
	$EnvVars = @()
	foreach ($V in (Get-Item env:*)) {
		$EnvVars += , @{
			Name = $V.Name
			Value = $V.Value
		}
	}
	Set-Variable -Name PwrSaveState -Value @{
		Vars = $Vars
		Env = $EnvVars
	} -Scope 'global'
}

function Restore-PSSessionState {
	Write-Debug 'pwr: restoring state'
	$State = (Get-Variable 'PwrSaveState' -Scope 'global').Value
	foreach ($V in $State.vars) {
		Set-Variable -Name "$($V.Name)" -Value $V.Value -Scope 'global' -Force -ErrorAction 'SilentlyContinue'
	}
	Remove-Item -Path 'env:*' -Force -ErrorAction 'SilentlyContinue'
	foreach ($E in $State.env) {
		Set-Item -Path "env:$($E.Name)" -Value $E.Value -Force -ErrorAction 'SilentlyContinue'
	}
	Set-Variable -Name PwrSaveState -Value $null -Scope 'Global'
}

function Clear-PSSessionState {
	Write-Debug 'pwr: clearing state'
	$DefaultVariableNames = '$', '?', '^', 'args', 'ConfirmPreference', 'ConsoleFileName', 'DebugPreference', 'Error', 'ErrorActionPreference', 'ErrorView', 'ExecutionContext', 'false', 'FormatEnumerationLimit', 'HOME', 'Host', 'InformationPreference', 'input', 'MaximumAliasCount', 'MaximumDriveCount', 'MaximumErrorCount', 'MaximumFunctionCount', 'MaximumHistoryCount', 'MaximumVariableCount', 'MyInvocation', 'NestedPromptLevel', 'null', 'OutputEncoding', 'PID', 'PROFILE', 'ProgressPreference', 'PSBoundParameters', 'PSCommandPath', 'PSCulture', 'PSDefaultParameterValues', 'PSEdition', 'PSEmailServer', 'PSHOME', 'PSScriptRoot', 'PSSessionApplicationName', 'PSSessionConfigurationName', 'PSSessionOption', 'PSUICulture', 'PSVersionTable', 'PWD', 'ShellId', 'StackTrace', 'true', 'VerbosePreference', 'WarningPreference', 'WhatIfPreference', 'PwrSaveState'
	$Vars = Get-Variable -Scope 'global'
	foreach ($Var in $Vars) {
		if ($Var.Name -notin $DefaultVariableNames) {
			Remove-Variable -Name "$($Var.Name)" -Scope 'global' -Force -ErrorAction 'SilentlyContinue'
		}
	}
	foreach ($Key in [Environment]::GetEnvironmentVariables([EnvironmentVariableTarget]::User).keys) {
		if ($Key -notin 'temp', 'tmp', 'pwrhome') {
			Remove-Item "env:$Key" -Force -ErrorAction SilentlyContinue
		}
	}
	Remove-Item 'env:PwrLoadedPackages' -Force -ErrorAction SilentlyContinue
}

function Remove-Directory($Dir) {
	$Wh = "${Dir}_wh_"
	try {
		Move-Item $Dir -Destination $Wh
	} catch {
		Write-PwrFatal "pwr: cannot remove $Dir because it is being used by another process"
	}
	$Name = [IO.Path]::GetRandomFileName()
	$Empty = "$env:Temp\$Name"
	mkdir $Empty | Out-Null
	try {
		robocopy $Empty $Wh /purge /MT | Out-Null
		Remove-Item $Wh
	} finally {
		Remove-Item $Empty
	}
}

function Get-InstalledPwrPackages {
	$Pkgs = @{}
	Get-ChildItem -Path $PwrPkgPath | ForEach-Object {
		if ($_.Name -match '(.+)-([0-9].+)') {
			$Pkg = $Matches[1]
			$Ver = $Matches[2]
			$Pkgs.$Pkg += , $Ver
		}
	}
	return $Pkgs
}

function Resolve-PwrPackageOverrides {
	if (-not $Override) {
		return
	}
	if (-not $PwrConfig) {
		Write-PwrFatal 'pwr: no configuration found to override'
	}
	$PkgOverride = @{}
	foreach ($P in $Packages) {
		$Pkg = Split-PwrPackage $P
		$PkgOverride.$($Pkg.name) = $Pkg
	}
	$Pkgs = @()
	foreach ($P in $PwrConfig.Packages) {
		$Split = Split-PwrPackage $P
		$Pkg = $PkgOverride.$($Split.name)
		if ($Pkg) {
			if ($Pkg.local) {
				Write-PwrFatal "pwr: tried to override local package $P"
			}
			$Over = "$($Pkg.name):$($Pkg.version):$($Pkg.config)"
			Write-Debug "pwr: overriding $P with $Over"
			$Pkgs += $Over
			$PkgOverride.Remove($Pkg.name)
		} else {
			$Pkgs += $P
		}
	}
	foreach ($Key in $PkgOverride.keys) {
		if ($PkgOverride.$Key.local) {
			Write-PwrFatal "pwr: tried to override local package $Key"
		} else {
			Write-PwrFatal "pwr: cannot override absent package ${Key}:$($PkgOverride.$Key.version)"
		}
	}
	[string[]]$script:Packages = $Pkgs
}

function Enter-Shell {
	if ($env:InPwrShell) {
		Write-PwrFatal "pwr: cannot start a new shell session while one is in progress; use command 'exit' to end the current session"
	}
	Assert-NonEmptyPwrPackages
	$Pkgs = @()
	foreach ($P in $Packages) {
		$Pkg = Assert-PwrPackage $P
		if (-not (Test-PwrPackage $Pkg)) {
			Invoke-PwrPackagePull $Pkg
		}
		$Pkgs += , $Pkg
	}
	Save-PSSessionState
	$env:InPwrShell = $true
	Clear-PSSessionState
	foreach ($P in $Pkgs) {
		try {
			Invoke-PwrPackageShell $P
		} catch {
			Restore-PSSessionState
			$env:InPwrShell = $null
			throw $_
		}
		Write-PwrHost -ForegroundColor Blue -NoNewline 'pwr:'
		Write-PwrHost " using $($P.ref)"
	}
	if (-not (Get-Command pwr -ErrorAction 'SilentlyContinue')) {
		$Pwr = Split-Path $script:MyInvocation.MyCommand.Path -Parent
		$env:Path = "$env:Path;$Pwr"
	}
	$env:Path = "$env:Path;\windows;\windows\system32;\windows\system32\windowspowershell\v1.0"
}

function Exit-Shell {
	if ($env:InPwrShell) {
		Restore-PSSessionState
		$env:InPwrShell = $null
		Write-Debug 'pwr: shell session closed'
	} else {
		Write-PwrFatal 'pwr: no shell session is in progress'
	}
}

function Invoke-PwrScripts {
	if ($PwrConfig.Scripts) {
		$Name = $Run[0]
		if ($PwrConfig.Scripts.$Name) {
			$RunCmd = [String]::Format($PwrConfig.Scripts.$Name, [object[]]$Run)
			if ($env:InPwrShell) {
				Write-PwrFatal "pwr: cannot invoke script due to shell session already in progress"
			}
			try {
				Enter-Shell
			} catch {
				exit 1
			}
			try {
				Invoke-Expression $RunCmd
			} catch {
				$ErrorMessage = $_.ToString().Trim()
			} finally {
				if ($env:InPwrShell) {
					Exit-Shell
				}
			}
			if ($ErrorMessage) {
				Write-PwrFatal "pwr: script '$Name' failed to execute$(if ($ErrorMessage.Length -gt 0) { '' } else { ', ' + $ErrorMessage.Substring(0, 1).ToLower() + $ErrorMessage.Substring(1) })"
			}
		} else {
			Write-PwrFatal "pwr: no declared script '$Name'"
		}
	} else {
		Write-PwrFatal "pwr: no scripts declared in $PwrConfig"
	}
}

$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'
$PwrPath = if ($env:PwrHome) { $env:PwrHome } else { "$env:appdata\pwr" }
$PwrWebPath = 'C:\Windows\System32\curl.exe'
$PwrPkgPath = "$PwrPath\pkg"
$env:PwrVersion = '0.4.21'
Compare-PwrTags

if (-not $Run) {
	switch ($Command) {
		{$_ -in 'v', 'version'} {
			if ($AssertMinimum) {
				$local:CurVer = [SemanticVersion]::new([string]"$env:PwrVersion")
				$local:MinVer = [SemanticVersion]::new([string]"$AssertMinimum")
				if ($CurVer.CompareTo($MinVer) -lt 0) {
					Write-PwrFatal "$env:PwrVersion does not meet the minimum version $AssertMinimum"
				}
			} else {
				Write-PwrOutput "pwr: version $env:PwrVersion"
			}
			exit
		}
		{$_ -in '', 'h', 'help'} {
			Get-Help $MyInvocation.MyCommand.Path -Detailed
			exit
		}
		'update' {
			if ($Offline) {
				Write-PwrFatal 'pwr: cannot update while running offline'
			} else {
				$PwrCmd = "$PwrPath\cmd"
				mkdir $PwrCmd -Force | Out-Null
				Invoke-PwrWebRequest -UseBasicParsing 'https://api.github.com/repos/airpwr/airpwr/contents/src/pwr.ps1' | ConvertFrom-Json | ForEach-Object {
					$Content = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_.Content))
					[IO.File]::WriteAllText("$PwrCmd\pwr.ps1", $Content)
				}
				$UserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
				if (-not $UserPath.Contains($PwrCmd)) {
					[Environment]::SetEnvironmentVariable('Path', "$UserPath;$PwrCmd", 'User')
				}
				if (-not ${env:Path}.Contains($PwrCmd)) {
					$env:Path = "$env:Path;$PwrCmd"
				}
				& "$PwrCmd\pwr.ps1" version
			}
			exit
		}
		'exit' {
			Exit-Shell
			exit
		}
	}
}

function Get-PwrConfig {
	$PwrCfgDir = $ExecutionContext.SessionState.Path.CurrentLocation
	do {
		$PwrCfg = "$PwrCfgDir\pwr.json"
		if (Test-Path -Path $PwrCfg -PathType Leaf) {
			try {
				return $PwrCfg, (Get-Content $PwrCfg | ConvertFrom-Json)
			} catch {
				Write-PwrFatal "pwr: bad JSON parse of file $PwrCfg - $_"
			}
		}
		$PwrCfgDir = Split-Path $PwrCfgDir -Parent
	} while ($PwrCfgDir.Length -gt 0)
}

$PwrConfigPath, $PwrConfig = Get-PwrConfig
$PwrAuths = Get-Content "$PwrPath\auths.json" -ErrorAction 'SilentlyContinue' | ConvertFrom-Json | ConvertTo-HashTable
$PwrRepositories = Get-PwrRepositories
Get-PwrPackages
Resolve-PwrPackageOverrides

if ($Run) {
	Assert-NonEmptyPwrPackages
	Invoke-PwrScripts
	exit
}

switch ($Command) {
	'fetch' {
		Assert-NonEmptyPwrPackages
		foreach ($P in $Packages) {
			$Pkg = Assert-PwrPackage $P
			if ($Pkg.Local) {
				Write-PwrFatal "pwr: tried to fetch local package $($Pkg.ref)"
			}
			Invoke-PwrPackagePull $Pkg
		}
	}
	'load' {
		Assert-NonEmptyPwrPackages
		$_Path = $env:Path
		Clear-Item env:Path
		try {
			foreach ($P in $Packages) {
				$Pkg = Assert-PwrPackage $P
				if (-not (Test-PwrPackage $Pkg)) {
					Invoke-PwrPackagePull $Pkg
				}
				if (-not "$env:PwrLoadedPackages".Contains($Pkg.ref)) {
					Invoke-PwrPackageShell $Pkg
					$env:PwrLoadedPackages = "$($Pkg.ref) $env:PwrLoadedPackages"
					Write-PwrHost -ForegroundColor Blue 'pwr:' -NoNewline
					Write-PwrHost " loaded $($Pkg.ref)"
				} elseif (Test-PwrPackage $Pkg) {
					Write-PwrOutput "pwr: $($Pkg.ref) already loaded"
				}
			}
			$env:Path = "$env:Path;$_Path"
		} catch {
			$env:Path = $_Path
		}
	}
	{$_ -in 'sh', 'shell'} {
		try {
			Enter-Shell
		} catch {
			exit 1
		}
	}
	'ls-config' {
		foreach ($P in $Packages) {
			$Pkg = Assert-PwrPackage $P
			if (-not (Test-PwrPackage $Pkg)) {
				Write-PwrFatal "pwr: package $($Pkg.ref) is not installed"
			}
			$local:PkgPath = Resolve-PwrPackge $Pkg
			$local:PwrCfg = Get-Content -Raw "$local:PkgPath\.pwr" | ConvertFrom-Json | ConvertTo-HashTable
			Write-PwrOutput "$($Pkg.ref)"
			$local:Configs = @('default')
			foreach ($local:Key in $local:PwrCfg.keys) {
				if (($local:Key -eq 'env') -or ($local:Key -eq 'var')) {
					continue
				}
				$local:Configs += $local:Key
			}
			foreach ($local:Config in ($local:Configs | Sort-Object)) {
				Write-PwrOutput "  $local:Config"
			}
		}
	}
	{$_ -in 'ls', 'list'} {
		if ($Installed) {
			Get-InstalledPwrPackages | Format-Table
			break
		}
		foreach ($Repo in $PwrRepositories) {
			if (($Packages.count -eq 1) -and ($Packages[0] -match '[^:]+')) {
				$Pkg = $Matches[0]
				Write-PwrOutput "pwr: $Pkg[$($Repo.uri)]"
				if ($Repo.Packages.$Pkg) {
					Write-PwrOutput $Repo.Packages.$Pkg | Format-List
				} else {
					Write-PwrOutput '<none>'
				}
			} else {
				Write-PwrOutput "pwr: [$($Repo.uri)]"
				if ('' -ne $Repo.Packages) {
					Write-PwrOutput $Repo.Packages | Format-List
				} else {
					Write-PwrOutput '<none>'
				}
			}
		}
	}
	{$_ -in 'rm', 'remove'} {
		if ($DaysOld) {
			if ($Packages.Count -gt 0) {
				Write-PwrFatal 'pwr: -DaysOld not compatible with -Packages'
			}
			$Pkgs = Get-InstalledPwrPackages
			foreach ($Name in $Pkgs.keys) {
				foreach ($Ver in $Pkgs.$Name) {
					$PkgRoot = "$PwrPkgPath\$Name-$Ver"
					try {
						$Item = Get-ChildItem -Path "$PkgRoot\.pwr"
					} catch {
						Write-PwrWarning "pwr: $PkgRoot is not a pwr package; it should be removed manually"
						continue
					}
					$Item.LastAccessTime = $Item.LastAccessTime
					$Old = $Item.LastAccessTime -lt ((Get-Date) - (New-TimeSpan -Days $DaysOld))
					if ($Old -and $PSCmdlet.ShouldProcess("${Name}:$Ver", 'remove pwr package')) {
						Write-PwrHost "pwr: removing ${Name}:$Ver ... " -NoNewline
						Remove-Directory $PkgRoot
						Write-PwrHost 'done.'
					}
				}
			}
		} else {
			Assert-NonEmptyPwrPackages
			foreach ($P in $Packages) {
				$Pkg = Assert-PwrPackage $P
				if ($Pkg.Local) {
					Write-PwrFatal "pwr: tried to remove local package $($Pkg.ref)"
				} elseif (Test-PwrPackage $Pkg) {
					if ($PSCmdlet.ShouldProcess($Pkg.ref, 'remove pwr package')) {
						Write-PwrHost "pwr: removing $($Pkg.ref) ... " -NoNewline
						$Path = Resolve-PwrPackge $Pkg
						Remove-Directory $Path
						Write-PwrHost 'done.'
					}
				} else {
					Write-PwrOutput "pwr: $($Pkg.ref) not found"
				}
			}
		}
	}
	Default {
		Write-PwrHost -ForegroundColor Red "pwr: no such command '$Command'"
		Write-PwrFatal "     use 'pwr help' for a list of commands"
	}
}
