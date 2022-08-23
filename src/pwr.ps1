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
		$This.Init($Tag, $Pattern)
	}

	SemanticVersion([string]$Version) {
		$This.Init($Version, '^([0-9]+)\.([0-9]+)\.([0-9]+)(\+[0-9]+)?$')
	}

	SemanticVersion() { }

	[bool]LaterThan([object]$Obj) {
		return $This.CompareTo($Obj) -gt 0
	}

	[int]CompareTo([object]$Obj) {
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

	[string]ToString() {
		return "$($This.Major).$($This.Minor).$($This.Patch)$(if ($This.Build) { "+$($This.Build)" })"
	}

}

function global:Prompt {
	if ($env:InPwrShell) {
		Write-Host -ForegroundColor Blue 'pwr:' -NoNewline
		Write-Host " $($ExecutionContext.SessionState.Path.CurrentLocation)$('>' * ($NestedPromptLevel + 1))" -NoNewline
		return ' '
	} else {
		"PS $($ExecutionContext.SessionState.Path.CurrentLocation)$('>' * ($NestedPromptLevel + 1)) "
	}
}

# Required for tar.exe and curl.exe
if ([Environment]::OSVersion.Version.Build -lt 17063) {
	Write-PwrFatal "windows build version $([Environment]::OSVersion.Version.Build) does not meet minimum required build version 17063`n     update windows to use pwr"
}

function Write-PwrOutput {
	if (-not $Quiet -and -not $Silent) {
		Write-Host -ForegroundColor Blue 'pwr: ' -NoNewline
		Write-Host @Args
	}
}

function Write-PwrHost {
	if (-not $Quiet -and -not $Silent) {
		Write-Host @Args
	}
}

function Write-PwrDebug($Message) {
	Write-Debug "pwr: $Message"
}

function Write-PwrFatal($Message) {
	if (-not $Silent) {
		Write-Host -ForegroundColor Red "pwr: $Message"
	}
	exit 1
}

function Write-PwrThrow($Message) {
	if (-not $Silent) {
		Write-Host -ForegroundColor Red "pwr: $Message"
	}
	throw $Message
}

function Write-PwrWarning($Message) {
	if (-not $Silent) {
		Write-Host -ForegroundColor Yellow "pwr: $Message"
	}
}

function Invoke-PwrWebRequest($Uri, $Headers, $OutFile, [switch]$UseBasicParsing) {
	if ($Offline) {
		Write-PwrThrow 'cannot web request while running offline'
	}
	$Expr = "$env:HOMEDRIVE\Windows\System32\curl.exe -s -L --url '$Uri'"
	foreach ($K in $Headers.Keys) {
		$Expr += " --header '${K}: $($Headers.$K)'"
	}
	if ($OutFile) {
		$Expr += " --output '$OutFile'"
	}
	return Invoke-Expression $Expr
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
	$Resp = Invoke-PwrWebRequest "https://auth.docker.io/token?service=registry.docker.io&scope=repository:$($Repo.Scope):pull"
	return ($Resp | ConvertFrom-Json).Token
}

function Get-ImageManifest($Pkg) {
	$Headers = @{'Accept' = 'application/vnd.docker.distribution.manifest.v2+json'}
	if ($Pkg.Repo.Headers.Authorization) {
		$Headers.Authorization = $Pkg.Repo.Headers.Authorization
	} elseif ($Pkg.Repo.IsDocker) {
		$Headers.Authorization = "Bearer $(Get-DockerToken $Pkg.Repo)"
	}
	$Resp = Invoke-PwrWebRequest "$($Pkg.Repo.Uri)/manifests/$($Pkg.Tag)" -Headers $Headers -UseBasicParsing
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
		Invoke-PwrWebRequest "$($Repo.Uri)/blobs/$Digest" -OutFile $Tmp -Headers $Headers
	} else {
		Write-PwrHost 'using cache ... ' -NoNewline
	}
	& "$env:HOMEDRIVE\Windows\System32\tar.exe" -xzf $Tmp -C $Out --exclude 'Hives/*' --strip-components 1
	Remove-Item $Tmp
}

function Get-RepoTags($Repo) {
	$Headers = @{}
	if ($Repo.Headers.Authorization) {
		$Headers.Authorization = $Repo.Headers.Authorization
	} elseif ($Repo.IsDocker) {
		$Headers.Authorization = "Bearer $(Get-DockerToken $Repo)"
	}
	$Resp = Invoke-PwrWebRequest "$($Repo.Uri)/tags/list" -Headers $Headers -UseBasicParsing
	return [string]$Resp | ConvertFrom-Json
}

function Resolve-PwrPackge($Pkg) {
	if ($Pkg.Local) {
		return $Pkg.Path
	} else {
		return "$PwrPkgPath\$($Pkg.Tag)"
	}
}

function Split-PwrPackage($Pkg) {
	if ($Pkg.StartsWith('file:///')) {
		$Split = $Pkg.Split('<')
		$Uri = $Split[0].Trim()
		return @{
			Name = $Uri
			Ref = $Uri
			Local = $true
			Path = (Resolve-Path $Uri.Substring(8)).Path
			Config = if ($Split[1]) { $Split[1].Trim() } else { 'default' }
		}
	}
	$Split = $Pkg.Split(':')
	$Props = @{
		Name = $Split[0]
		Version = 'latest'
		Config = 'default'
	}
	if ($Split.Count -ge 2 -and ($Split[1] -ne '')) {
		$Props.Version = $Split[1]
	}
	if ($Split.Count -ge 3 -and ($Split[2] -ne '')) {
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
		Write-PwrFatal "no package named $Name$(if ($Matcher) { " matching $Matcher"} else { '' })"
	}
	return $Latest.ToString()
}

function Assert-PwrPackage($Pkg) {
	$P = Split-PwrPackage $Pkg
	if ($P.Local) {
		return $P
	}
	$Name = $P.Name
	$Version = $P.Version
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
			$P.Ref = "$($P.Name):$($P.Version)"
			return $P
		}
	}
	if (-not $Offline -and -not $Fetch) {
		$script:Fetch = $true
		Get-PwrPackages
		return Assert-PwrPackage $Pkg
	}
	Write-PwrFatal "no package for ${Name}:$Version"
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
	$Tags = Get-Content $Cache -ErrorAction SilentlyContinue | ConvertFrom-Json
	$Latest = [SemanticVersion]::new()
	foreach ($Tag in $Tags) {
		$Ver = [SemanticVersion]::new($Tag.Name.Substring(1))
		if ($Ver.LaterThan($Latest)) {
			$Latest = $Ver
		}
	}
	if ($Latest.LaterThan([SemanticVersion]::new($env:PwrVersion))) {
		Write-PwrOutput -ForegroundColor Green "a new version ($Latest) is available!"
		Write-PwrOutput -ForegroundColor Green "use command 'update' to install"
	}
}

function Get-PwrPackages {
	foreach ($Repo in $PwrRepositories) {
		$Cache = "$PwrPath\cache\$($Repo.Hash)"
		$CacheExists = Test-Path $Cache
		if ($CacheExists) {
			$LastWrite = [DateTime]::Parse((Get-Item $Cache).LastWriteTime)
			$OutOfDate = [DateTime]::Compare((Get-Date), $LastWrite + (New-TimeSpan -Days 1)) -gt 0
		}
		if ($Offline) {
			Write-PwrOutput 'skipping fetch tags while running offline'
		} elseif (-not $CacheExists -or $OutOfDate -or $Fetch) {
			try {
				Write-PwrOutput "fetching tags from $($Repo.Uri)"
				$TagList = Get-RepoTags $Repo
				$Pkgs = @{}
				$Names = @{}
				foreach ($Tag in $TagList.Tags) {
					if ($Tag -match '(.+)-([0-9].+)') {
						$Pkg = $Matches[1]
						$Ver = $Matches[2]
						$Names.$Pkg = $null
						$Pkgs.$Pkg = @($Pkgs.$Pkg) + @([SemanticVersion]::new($Ver)) | Sort-Object -Descending
					}
				}
				foreach ($Name in $Names.Keys) {
					$Pkgs.$Name = $Pkgs.$Name | ForEach-Object { $_.ToString() }
				}
				mkdir (Split-Path $Cache -Parent) -Force | Out-Null
				[IO.File]::WriteAllText($Cache, (ConvertTo-Json $Pkgs -Depth 50 -Compress))
			} catch {
				Write-PwrOutput -ForegroundColor Red "failed to fetch tags from $($Repo.Uri)"
				Write-Debug "    > $($Error[0])"
			}
		}
		$Repo.Packages = Get-Content $Cache -ErrorAction SilentlyContinue | ConvertFrom-Json
	}

}

function Test-PwrPackage($Pkg) {
	$PkgPath = Resolve-PwrPackge $Pkg
	return Test-Path "$PkgPath\.pwr"
}

function Invoke-PwrPackagePull($Pkg) {
	if (Test-PwrPackage $Pkg) {
		Write-PwrOutput "$($Pkg.Ref) already exists"
	} elseif ($Offline) {
		Write-PwrFatal "cannot fetch $($Pkg.Ref) while running offline"
	} else {
		Write-PwrOutput "fetching $($Pkg.Ref) ... " -NoNewline
		$Manifest = Get-ImageManifest $Pkg
		$PkgPath = Resolve-PwrPackge $Pkg
		mkdir $PkgPath -Force | Out-Null
		foreach ($Layer in $Manifest.Layers) {
			if ($Layer.MediaType -eq 'application/vnd.docker.image.rootfs.diff.tar.gzip') {
				Invoke-PullImageLayer $PkgPath $Pkg.Repo $Layer.Digest
			}
		}
		Write-PwrHost 'done.'
	}
}

function Invoke-PwrPackageShell($Pkg) {
	$PkgPath = Resolve-PwrPackge $Pkg
	if ($Offline -and -not (Test-PwrPackage $Pkg)) {
		Write-PwrThrow "cannot resolve package $($Pkg.Ref) while running offline"
	}
	$Vars = (Get-Content -Path "$PkgPath\.pwr").Replace('${.}', (Resolve-Path $PkgPath).Path.Replace('\', '\\')) | ConvertFrom-Json | ConvertTo-HashTable
	if ($Pkg.Config -eq 'default') {
		$PkgVar = $Vars
	} else {
		if (-not $Vars."$($Pkg.Config)") {
			Write-PwrThrow "no such configuration '$($Pkg.Config)' for $($Pkg.Ref)"
		}
		$PkgVar = $Vars."$($Pkg.Config)"
	}
	Format-Table $PkgEnv
	# Vars
	foreach ($K in $PkgVar.Var.Keys) {
		Set-Variable -Name $K -Value $PkgVar.Var.$K -Scope Global
	}
	# Env
	foreach ($K in $PkgVar.Env.Keys) {
		$Prefix = ''
		if ($K -eq 'path') {
			$Prefix += "${env:Path};"
		}
		Set-Item "env:$K" "$Prefix$($PkgVar.Env.$K)"
	}
	$Item = Get-ChildItem -Path "$PkgPath\.pwr"
	$Item.LastAccessTime = (Get-Date)
}

function Assert-NonEmptyPwrPackages {
	if ($Packages.Count -gt 0) {
		return
	} elseif ($PwrConfig.Packages.Count -gt 0) {
		Write-PwrDebug "using config at $PwrConfigPath"
		$script:Packages = $PwrConfig.Packages
	} elseif ($PwrConfig) {
		Write-PwrFatal "no packages declared in $PwrConfigPath"
	} else {
		Write-PwrFatal 'no packages provided'
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
		foreach ($Auth in $PwrAuths.Keys) {
			$AuthUri = if (-not $Auth.StartsWith('http')) { "https://$Auth" } else { $Auth }
			if ($Uri.StartsWith($AuthUri)) {
				if ($PwrAuths.$Auth.Basic) {
					$Headers.Authorization = "Basic $($PwrAuths.$Auth.Basic)"
					break
				}
			}
		}
		$Repository = @{
			URI = $Uri
			Scope = $Uri.Substring($Uri.IndexOf('/v2/') + 4)
			Hash = Get-StringHash $Uri
		}
		if ($Headers.Count -gt 0) {
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
	Write-PwrDebug 'saving state'
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
	} -Scope Global
}

function Restore-PSSessionState {
	Write-PwrDebug 'restoring state'
	$State = (Get-Variable 'PwrSaveState' -Scope Global).Value
	foreach ($V in $State.Vars) {
		Set-Variable -Name "$($V.Name)" -Value $V.Value -Scope Global -Force -ErrorAction SilentlyContinue
	}
	Remove-Item -Path 'env:*' -Force -ErrorAction SilentlyContinue
	foreach ($E in $State.Env) {
		Set-Item -Path "env:$($E.Name)" -Value $E.Value -Force -ErrorAction SilentlyContinue
	}
	Set-Variable -Name PwrSaveState -Value $null -Scope Global
}

function Clear-PSSessionState {
	Write-PwrDebug 'clearing state'
	$DefaultVariableNames = '$', '?', '^', 'args', 'ConfirmPreference', 'ConsoleFileName', 'DebugPreference', 'Error', 'ErrorActionPreference', 'ErrorView', 'ExecutionContext', 'false', 'FormatEnumerationLimit', 'HOME', 'Host', 'InformationPreference', 'input', 'MaximumAliasCount', 'MaximumDriveCount', 'MaximumErrorCount', 'MaximumFunctionCount', 'MaximumHistoryCount', 'MaximumVariableCount', 'MyInvocation', 'NestedPromptLevel', 'null', 'OutputEncoding', 'PID', 'PROFILE', 'ProgressPreference', 'PSBoundParameters', 'PSCommandPath', 'PSCulture', 'PSDefaultParameterValues', 'PSEdition', 'PSEmailServer', 'PSHOME', 'PSScriptRoot', 'PSSessionApplicationName', 'PSSessionConfigurationName', 'PSSessionOption', 'PSUICulture', 'PSVersionTable', 'PWD', 'ShellId', 'StackTrace', 'true', 'VerbosePreference', 'WarningPreference', 'WhatIfPreference', 'PwrSaveState'
	$Vars = Get-Variable -Scope Global
	foreach ($Var in $Vars) {
		if ($Var.Name -notin $DefaultVariableNames) {
			Remove-Variable -Name "$($Var.Name)" -Scope Global -Force -ErrorAction SilentlyContinue
		}
	}
	foreach ($Key in [Environment]::GetEnvironmentVariables([EnvironmentVariableTarget]::User).Keys) {
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
		Write-PwrFatal "cannot remove $Dir because it is being used by another process"
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
		Write-PwrFatal 'no configuration found to override'
	}
	$PkgOverride = @{}
	foreach ($P in $Packages) {
		$Pkg = Split-PwrPackage $P
		$PkgOverride.$($Pkg.Name) = $Pkg
	}
	$Pkgs = @()
	foreach ($P in $PwrConfig.Packages) {
		$Split = Split-PwrPackage $P
		$Pkg = $PkgOverride.$($Split.Name)
		if ($Pkg) {
			if ($Pkg.Local) {
				Write-PwrFatal "tried to override local package $P"
			}
			$Over = "$($Pkg.Name):$($Pkg.Version):$($Pkg.Config)"
			Write-PwrDebug "overriding $P with $Over"
			$Pkgs += $Over
			$PkgOverride.Remove($Pkg.Name)
		} else {
			$Pkgs += $P
		}
	}
	foreach ($Key in $PkgOverride.Keys) {
		if ($PkgOverride.$Key.Local) {
			Write-PwrFatal "tried to override local package $Key"
		} else {
			Write-PwrFatal "cannot override absent package ${Key}:$($PkgOverride.$Key.Version)"
		}
	}
	[string[]]$script:Packages = $Pkgs
}

function Enter-Shell {
	if ($env:InPwrShell) {
		Write-PwrFatal "cannot start a new shell session while one is in progress; use command 'exit' to end the current session"
	}
	Assert-NonEmptyPwrPackages
	$Pkgs = @()
	Lock-PwrLock
	try {
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
			Write-PwrOutput "using $($P.Ref)"
		}
	} finally {
		Unlock-PwrLock
	}
	if (-not (Get-Command pwr -ErrorAction SilentlyContinue)) {
		$Pwr = Split-Path $script:MyInvocation.MyCommand.Path -Parent
		$env:Path = "$env:Path;$Pwr"
	}
	$env:Path = "$env:Path;\windows;\windows\system32;\windows\system32\windowspowershell\v1.0"
}

function Exit-Shell {
	if ($env:InPwrShell) {
		Restore-PSSessionState
		$env:InPwrShell = $null
		Write-PwrDebug 'shell session closed'
	} else {
		Write-PwrFatal 'no shell session is in progress'
	}
}

function Invoke-PwrScripts {
	if ($PwrConfig.Scripts) {
		$Name = $Run[0]
		if ($PwrConfig.Scripts.$Name) {
			$RunCmd = [String]::Format($PwrConfig.Scripts.$Name, [object[]]$Run)
			if ($env:InPwrShell) {
				Write-PwrFatal "cannot invoke script due to shell session already in progress"
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
				Write-PwrFatal "script '$Name' failed to execute$(if ($ErrorMessage.Length -gt 0) { '' } else { ', ' + $ErrorMessage.Substring(0, 1).ToLower() + $ErrorMessage.Substring(1) })"
			}
		} else {
			Write-PwrFatal "no declared script '$Name'"
		}
	} else {
		Write-PwrFatal "no scripts declared in $PwrConfig"
	}
}

$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'
$PwrPath = if ($env:PwrHome) { $env:PwrHome } else { "$env:AppData\pwr" }
$PwrPkgPath = "$PwrPath\pkg"
$env:PwrVersion = '0.4.22'

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
				Write-PwrOutput "version $env:PwrVersion"
			}
		}
		{$_ -in '', 'h', 'help'} {
			Get-Help $MyInvocation.MyCommand.Path -Detailed
		}
		'update' {
			if ($Offline) {
				Write-PwrFatal 'cannot update while running offline'
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
		}
		'exit' {
			Exit-Shell
		}
	}
	exit
}

function Get-PwrConfig {
	$PwrCfgDir = $ExecutionContext.SessionState.Path.CurrentLocation
	do {
		$PwrCfg = "$PwrCfgDir\pwr.json"
		if (Test-Path -Path $PwrCfg -PathType Leaf) {
			try {
				return $PwrCfg, (Get-Content $PwrCfg | ConvertFrom-Json)
			} catch {
				Write-PwrFatal "bad JSON parse of file $PwrCfg - $_"
			}
		}
		$PwrCfgDir = Split-Path $PwrCfgDir -Parent
	} while ($PwrCfgDir.Length -gt 0)
}

function Lock-PwrLock {
	try {
		New-Item $PwrLock -ItemType File
	} catch {
		Write-PwrFatal "already fetching or removing package`n     if this isn't the case, manually delete $PwrLock"
	}
}

function Unlock-PwrLock {
	try {
		Remove-Item $PwrLock
	} catch {
		Write-PwrWarning "lock file $PwrLock could not be removed`n     ensure this file does not exist before running pwr again"
	}
}

Compare-PwrTags
$PwrConfigPath, $PwrConfig = Get-PwrConfig
$PwrLock = "$PwrPath\pwr.lock"
$PwrAuths = Get-Content "$PwrPath\auths.json" -ErrorAction SilentlyContinue | ConvertFrom-Json | ConvertTo-HashTable
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
		Lock-PwrLock
		try {
			foreach ($P in $Packages) {
				$Pkg = Assert-PwrPackage $P
				if ($Pkg.Local) {
					Write-PwrFatal "tried to fetch local package $($Pkg.Ref)"
				}
				Invoke-PwrPackagePull $Pkg
			}
		} finally {
			Unlock-PwrLock
		}
	}
	'load' {
		Assert-NonEmptyPwrPackages
		Lock-PwrLock
		$_Path = $env:Path
		try {
			Clear-Item env:Path
			foreach ($P in $Packages) {
				$Pkg = Assert-PwrPackage $P
				if (-not (Test-PwrPackage $Pkg)) {
					Invoke-PwrPackagePull $Pkg
				}
				if (-not "$env:PwrLoadedPackages".Contains($Pkg.Ref)) {
					Invoke-PwrPackageShell $Pkg
					$env:PwrLoadedPackages = "$($Pkg.Ref) $env:PwrLoadedPackages"
					Write-PwrOutput "loaded $($Pkg.Ref)"
				} elseif (Test-PwrPackage $Pkg) {
					Write-PwrOutput "$($Pkg.Ref) already loaded"
				}
			}
			$env:Path = "$env:Path;$_Path"
		} catch {
			$env:Path = $_Path
			exit 1
		} finally {
			Unlock-PwrLock
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
				Write-PwrFatal "package $($Pkg.Ref) is not installed"
			}
			$local:PkgPath = Resolve-PwrPackge $Pkg
			$local:PwrCfg = Get-Content -Raw "$local:PkgPath\.pwr" | ConvertFrom-Json | ConvertTo-HashTable
			Write-PwrHost "$($Pkg.Ref)"
			$local:Configs = @('default')
			foreach ($local:Key in $local:PwrCfg.Keys) {
				if (($local:Key -eq 'env') -or ($local:Key -eq 'var')) {
					continue
				}
				$local:Configs += $local:Key
			}
			foreach ($local:Config in ($local:Configs | Sort-Object)) {
				Write-PwrHost "  $local:Config"
			}
		}
	}
	{$_ -in 'ls', 'list'} {
		if ($Installed) {
			Get-InstalledPwrPackages | Format-Table
			break
		}
		foreach ($Repo in $PwrRepositories) {
			if (($Packages.Count -eq 1) -and ($Packages[0] -match '[^:]+')) {
				$Pkg = $Matches[0]
				Write-PwrOutput "$Pkg[$($Repo.Uri)]"
				if ($Repo.Packages.$Pkg -and -not $Quiet -and -not $Silent) {
					$Repo.Packages.$Pkg | Format-List
				} else {
					Write-PwrHost '<none>'
				}
			} else {
				Write-PwrOutput "[$($Repo.Uri)]"
				if ('' -ne $Repo.Packages -and -not $Quiet -and -not $Silent) {
					''
					$Repo.Packages | Format-List | Out-String -Stream | Where-Object{ $_.Length -gt 0 } | Sort-Object
					''
				} else {
					Write-PwrHost '<none>'
				}
			}
		}
	}
	{$_ -in 'rm', 'remove'} {
		Lock-PwrLock
		try {
			if ($DaysOld) {
				if ($Packages.Count -gt 0) {
					Write-PwrFatal '-DaysOld not compatible with -Packages'
				}
				$Pkgs = Get-InstalledPwrPackages
				foreach ($Name in $Pkgs.Keys) {
					foreach ($Ver in $Pkgs.$Name) {
						$PkgRoot = "$PwrPkgPath\$Name-$Ver"
						try {
							$Item = Get-ChildItem -Path "$PkgRoot\.pwr"
						} catch {
							Write-PwrWarning "$PkgRoot is not a pwr package; it should be removed manually"
							continue
						}
						$Item.LastAccessTime = $Item.LastAccessTime
						$Old = $Item.LastAccessTime -lt ((Get-Date) - (New-TimeSpan -Days $DaysOld))
						if ($Old -and $PSCmdlet.ShouldProcess("${Name}:$Ver", 'remove pwr package')) {
							Write-PwrOutput "removing ${Name}:$Ver ... " -NoNewline
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
						Write-PwrFatal "tried to remove local package $($Pkg.Ref)"
					} elseif (Test-PwrPackage $Pkg) {
						if ($PSCmdlet.ShouldProcess($Pkg.Ref, 'remove pwr package')) {
							Write-PwrOutput "removing $($Pkg.Ref) ... " -NoNewline
							$Path = Resolve-PwrPackge $Pkg
							Remove-Directory $Path
							Write-PwrHost 'done.'
						}
					} else {
						Write-PwrOutput -ForegroundColor Red "$($Pkg.Ref) not found"
					}
				}
			}
		} finally {
			Unlock-PwrLock
		}
	}
	Default {
		Write-PwrFatal "no such command '$Command'`n     use 'pwr help' for a list of commands"
	}
}
