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
	home			Displays the pwr home path
	help, h			Displays syntax and descriptive information for calling pwr
	version, v		Displays this verion of pwr
	prune			Removes out-of-date packages from the local machine
	remove, rm		Removes package data from the local machine
	update			Updates the pwr command to the latest version
	which			Displays the package version and digest
	where			Displays the package install path
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
.PARAMETER Info
	Displays messages written to the information stream (6), otherwise the InformationPreference value is respected
.PARAMETER Quiet
	Suppresses messages written to the success stream (1), debug stream (5), and information stream (6)
.PARAMETER Silent
	Suppresses messages written to the success stream (1), error stream (2), warning stream (3), debug stream (5), and information stream (6)
.PARAMETER AssertMinimum
	Writes an error if the provided semantic version (a.b.c) is later than the pwr version
	Must be used in conjunction with the 'version' command
.PARAMETER Override
	Overrides 'pwr.json' package versions with the versions provided by the `Packages` parameter
	The package must be declared in the configuration file
	The package must not be expressed by a file URI
.PARAMETER Installed
	Use with the `list` command to enumerate the packages installed on the local machine
.PARAMETER WhatIf
	Use with the `remove` or `prune` commands to show the dry-run of packages that will be removed
.PARAMETER Run
	Executes the user-defined script inside a shell session
	The script is declared like `{ ..., "scripts": { "name": "something to run" } }` in 'pwr.json'
	To specify a script with parameters, declare it like `{ ..., "scripts": { "name": { "format": "something to run --arg={1}" } } }` in 'pwr.json'
	Arguments may be provided to the formatted script, referenced in the format as {1}, {2}, etc. ({0} refers to the script name)
	The format is interpreted by the string.Format method, with the values specified after the name of script
	Note: characters such as '{' and '}' need to be escaped by '{{' and '}}' respectively
	To specify a formatted script with default arguments, declare it like `{ ..., "scripts": { "name": { "format": "{0} {1}", "args": ["first"] } } }`
	These default arguments will be overridden by any value specified after the name of script, in the order provided
#>
[CmdletBinding(SupportsShouldProcess)]
param (
	[Parameter(Position = 0)]
	[ValidateSet('v', 'version', 'home', '', 'h', 'help', 'update', 'exit', 'fetch', 'load', 'sh', 'shell', 'ls-config', 'ls', 'list', 'prune', 'rm', 'remove', 'which', 'where')]
	[string]$Command,
	[Parameter(Position = 1)]
	[ValidatePattern('^((file:///.+)|([a-zA-Z0-9_-]+(:((([0-9]+\.){0,2}[0-9]+(\+[0-9]+)?)|latest|(?=:))(:([a-zA-Z0-9_-]+))?)?))$')]
	[string[]]$Packages,
	[string[]]$Repositories,
	[switch]$Fetch,
	[switch]$Installed,
	[ValidatePattern('^([0-9]+)\.([0-9]+)\.([0-9]+)$')]
	[string]$AssertMinimum,
	[ValidatePattern('^[1-9][0-9]*$')]
	[int]$DaysOld,
	[switch]$Offline,
	[switch]$Info,
	[switch]$Quiet,
	[switch]$Silent,
	[switch]$Override,
	[string[]]$Run
)

$WriteToHost = ($MyInvocation.ScriptLineNumber -eq 1) -and ($MyInvocation.OffsetInLine -eq 1) -and ($MyInvocation.PipelineLength -eq 1)

function Write-Pwr($Message, $ForegroundColor, [switch]$NoNewline, [switch]$Override) {
	if ($WriteToHost) {
		$PwrColor = if ($Override) { $ForegroundColor } else { 'Blue' }
		Write-Host 'pwr: ' -ForegroundColor $PwrColor -NoNewline
		if ($ForegroundColor) {
			Write-Host $Message -ForegroundColor $ForegroundColor -NoNewline:$NoNewline
		} else {
			Write-Host $Message -NoNewline:$NoNewline
		}
	} else {
		Write-Output "pwr: $Message"
	}
}

function Write-PwrFatal($Message) {
	if (-not $Silent) {
		if ($WriteToHost) {
			Write-Pwr $Message -ForegroundColor Red -Override
		} else {
			Write-Error "pwr: $Message" -ErrorAction Continue
		}
	}
	exit 1
}

function Assert-PwrArguments {
	if ($null -ne $Run) {
		if ($Command -notin '', 'shell', 'sh') {
			Write-PwrFatal "only commands 'shell', and '' are compatible with -Run: $Command"
		} elseif ($Run.Count -eq 0) {
			Write-PwrFatal 'no run arguments provided'
		}
	}
	if ($Override -and $Packages.Count -eq 0) {
		Write-PwrFatal 'expected packages for switch -Override'
	}
	if ($Installed -and $Command -notin 'ls', 'list') {
		Write-PwrFatal "only command 'list' is compatible with switch -Installed: $Command"
	}
	if ($AssertMinimum -and $Command -notin 'v', 'version') {
		Write-PwrFatal "only command 'version' is compatible with flag -AssertMinimum: $Command"
	}
}

Assert-PwrArguments

Class SemanticVersion : System.IComparable {

	[int]$Major = 0
	[int]$Minor = 0
	[int]$Patch = 0
	[int]$Build = 0

	hidden init([string]$Tag, [string]$Pattern) {
		if ($Tag -match $Pattern) {
			$this.Major = if ($Matches[1]) { $Matches[1] } else { 0 }
			$this.Minor = if ($Matches[2]) { $Matches[2] } else { 0 }
			$this.Patch = if ($Matches[3]) { $Matches[3] } else { 0 }
			$this.Build = if ($Matches[4]) { $Matches[4].Substring(1) } else { 0 }
		}
	}

	SemanticVersion([string]$Tag, [string]$Pattern) {
		$this.Init($Tag, $Pattern)
	}

	SemanticVersion([string]$Version) {
		$this.Init($Version, '^([0-9]+)\.([0-9]+)\.([0-9]+)([_+][0-9]+)?$')
	}

	SemanticVersion() { }

	[bool]Equals([object]$Obj) {
		return $this.CompareTo($Obj) -eq 0
	}

	[bool]LaterThan([object]$Obj) {
		return $this.CompareTo($Obj) -gt 0
	}

	[int]CompareTo([object]$Obj) {
		if ($Obj -isnot $this.GetType()) {
			throw "cannot compare types $($Obj.GetType()) and $($this.GetType())"
		} elseif ($this.Major -ne $Obj.Major) {
			return $this.Major - $Obj.Major
		} elseif ($this.Minor -ne $Obj.Minor) {
			return $this.Minor - $Obj.Minor
		} elseif ($this.Patch -ne $Obj.Patch) {
			return $this.Patch - $Obj.Patch
		} else {
			return $this.Build - $Obj.Build
		}
	}

	[string]ToString() {
		return "$($this.Major).$($this.Minor).$($this.Patch)$(if ($this.Build) { "+$($this.Build)" })"
	}

}

function global:Prompt {
	if ($env:PwrShellPackages) {
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
} elseif ($PSVersionTable.PSVersion.Major -lt 5) {
	Write-PwrFatal "powershell version $($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor) does not meet minimum required version 5.0"
}

function Write-PwrOutput($Message, $ForegroundColor, [switch]$NoNewline) {
	if (-not $Quiet -and -not $Silent) {
		Write-Pwr $Message -ForegroundColor $ForegroundColor -NoNewline:$NoNewline
	}
}

function Write-PwrHost($Message) {
	if (-not $Quiet -and -not $Silent) {
		Write-Output $Message
	}
}

function Write-PwrInfo($Message) {
	if (-not $Quiet -and -not $Silent) {
		if ($WriteToHost) {
			switch ($InformationPreference) {
				'Continue' {
					Write-Pwr $Message
				}
				'Inquire' {
					Write-Pwr $Message
					if (-not $PSCmdlet.ShouldContinue($null, $null)) {
						exit
					}
				}
				'Stop' {
					throw $Message
				}
			}
		} else {
			Write-Information "pwr: $Message" -InformationAction "$(if ($Info) { 'Continue' } else { $InformationPreference })"
		}
	}
}

function Write-PwrDebug($Message) {
	if (-not $Quiet -and -not $Silent) {
		if ($WriteToHost) {
			switch ($DebugPreference) {
				'Continue' {
					Write-Pwr $Message
				}
				'Inquire' {
					Write-Pwr $Message
					if (-not $PSCmdlet.ShouldContinue($null, $null)) {
						exit
					}
				}
				'Stop' {
					throw $Message
				}
			}
		} else {
			Write-Debug "pwr: $Message"
		}
	}
}

function Write-PwrThrow($Message) {
	if (-not $Silent) {
		if ($WriteToHost) {
			Write-Pwr $Message -ForegroundColor Red -Override
		} else {
			Write-Error "pwr: $Message" -ErrorAction Continue
		}
	}
	throw $Message
}

function Write-PwrWarning($Message) {
	if (-not $Silent) {
		if ($WriteToHost) {
			switch ($WarningPreference) {
				'Continue' {
					Write-Pwr $Message -ForegroundColor Yellow -Override
				}
				'Inquire' {
					Write-Pwr $Message -ForegroundColor Yellow -Override
					if (-not $PSCmdlet.ShouldContinue($null, $null)) {
						exit
					}
				}
				'Stop' {
					throw $Message
				}
			}
		} else {
			Write-Warning "pwr: $Message"
		}
	}
}

class PwrWebRequestResult {

	[string]$Output
	[bool]$IsPartial

	PwrWebRequestResult([string]$Output, [bool]$IsPartial) {
		$this.Output = $Output
		$this.IsPartial = $IsPartial
	}

	[string]ToString() {
		return $this.Output
	}

}

function Invoke-PwrWebRequest($Uri, $Headers, $OutFile, [switch]$UseBasicParsing) {
	if ($Offline) {
		Write-PwrThrow 'cannot web request while running offline'
	}
	$Expr = "$env:SYSTEMROOT\System32\curl.exe -s -L --url '$Uri'"
	foreach ($K in $Headers.Keys) {
		$Expr += " --header '${K}: $($Headers.$K)'"
	}
	if ($OutFile) {
		$Expr += " --output '$OutFile' -C -"
		$InitialSize = (Get-Item -ErrorAction SilentlyContinue $OutFile).Length
	}
	$Content = Invoke-Expression $Expr
	if ($global:LASTEXITCODE -eq 0) {
		return [PwrWebRequestResult]::new($Content, $false)
	} elseif ($OutFile -and $InitialSize -lt (Get-Item -ErrorAction SilentlyContinue $OutFile).Length) { # This is a partial download if the file size increased
		return [PwrWebRequestResult]::new($Content, $true)
	}
	Write-PwrFatal "command 'curl.exe' finished with non-zero exit value $global:LASTEXITCODE"
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
		if ($V -is [Array]) {
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

function Invoke-PullImageLayer($Out, $Ref, $Repo, $Digest) {
	$Tmp = "$env:Temp/$($Digest.Replace(':', '_')).tgz"
	if (-not ((Test-Path -Path $Tmp -PathType Leaf) -and (Get-FileHash -Path $Tmp -Algorithm SHA256).Hash -eq $Digest.Replace('sha256:', ''))) {
		$Headers = @{}
		do {
			if ($Repo.Headers.Authorization) {
				$Headers.Authorization = $Repo.Headers.Authorization
			} elseif ($Repo.IsDocker) {
				$Headers.Authorization = "Bearer $(Get-DockerToken $Repo)"
			}
		} while ((Invoke-PwrWebRequest "$($Repo.Uri)/blobs/$Digest" -OutFile $Tmp -Headers $Headers).IsPartial)
	} else {
		Write-PwrInfo "using cache for $Ref"
	}
	$Hash = "sha256:$((Get-FileHash -Path $Tmp -Algorithm SHA256).Hash)"
	if (-not (Test-Path -Path $Tmp -PathType Leaf) -or $Hash -ne $Digest) {
		Remove-Item $Tmp
		Write-PwrFatal "the download of layer$(if ($Hash.Length -gt 7) { " with digest $Hash" }) for package $Ref was corrupted and does not match expected digest $Digest"
	}
	return Start-Job -ScriptBlock {
		$Tmp, $Out = $Args
		& "$env:SYSTEMROOT\System32\tar.exe" -xzf $Tmp -C $Out --exclude 'Hives/*' --strip-components 1
		if ($global:LASTEXITCODE) {
			throw
		}
		Remove-Item $Tmp
	} -ArgumentList $Tmp, $Out
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

function Resolve-PwrPackage($Pkg) {
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
			Id = $Uri
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
	$Props.Id = if ($Props.Version -eq 'latest') { $Props.Name } else { "$($Props.Name):$($Props.Version)" }
	if ($Split.Count -ge 3 -and ($Split[2] -ne '')) {
		$Props.Config = $Split[2]
	}
	return $Props;
}

function Get-LatestVersion($Pkgs, $Version) {
	if ($Version -match '^([0-9]+)(\.[0-9]+)?(\.[0-9]+)?$') {
		$local:Major = [int]$Matches[1]
		$local:Minor = if ($Matches[2]) { [int]$Matches[2].Substring(1) }
		$local:Patch = if ($Matches[3]) { [int]$Matches[3].Substring(1) }
	}
	$Latest = $null
	foreach ($V in $Pkgs) {
		$Ver = [SemanticVersion]::new($V)
		if ((($null -eq $Latest) -or $Ver.LaterThan($Latest)) -and (($null -eq $local:Major) -or ($Ver.Major -eq $local:Major)) -and (($null -eq $local:Minor) -or ($Ver.Minor -eq $local:Minor)) -and (($null -eq $local:Patch) -or ($Ver.Patch -eq $local:Patch))) {
			$Latest = $Ver
		}
	}
	if (-not $Latest) {
		Write-PwrFatal "no package for $Name$(if ($Version) { ":$Version" })"
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
		} elseif ($Version -match '^([0-9]+\.){2}[0-9]+(\+[0-9]+)$' -and ($Version -in $Repo.Packages.$Name)) {
			$P.Tag = "$Name-$Version"
		} elseif ($Version -match '^[0-9]+(\.[0-9]+){0,2}$') {
			$Latest = Get-LatestVersion $Repo.Packages.$Name $Version
			$P.Tag = "$Name-$Latest"
			$P.Version = $Latest
		}
		if ($P.Tag) {
			$P.Tag = $P.Tag.Replace('+', '_')
			$P.Repo = $Repo
			$P.Ref = "$($P.Name):$($P.Version)$(if ($P.Config -ne 'default') { ":$($P.Config)" })"
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
	$Cache = "$PwrPath\cache\tags"
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
		} catch {
			Write-PwrWarning $_
		}
	}
	$Tags = Get-Content $Cache -ErrorAction SilentlyContinue | ConvertFrom-Json
	$Latest = [SemanticVersion]::new()
	foreach ($Tag in $Tags) {
		$Ver = [SemanticVersion]::new($Tag.Name.Substring(1))
		if ($Ver.LaterThan($Latest)) {
			$Latest = $Ver
		}
	}
	if ($Latest.LaterThan([SemanticVersion]::new("$env:PwrVersion"))) {
		Write-PwrOutput "a new version ($Latest) is available!" -ForegroundColor Green
		Write-PwrOutput "use command 'update' to install" -ForegroundColor Green
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
			Write-PwrInfo 'skipping fetch tags while running offline'
		} elseif (-not $CacheExists -or $OutOfDate -or $Fetch) {
			try {
				Write-PwrInfo "fetching tags from $($Repo.Uri)"
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
				Write-PwrOutput "failed to fetch tags from $($Repo.Uri)" -ForegroundColor Red
				Write-Debug "    > $($Error[0])"
			}
		}
		$Repo.Packages = Get-Content $Cache -ErrorAction SilentlyContinue | ConvertFrom-Json
	}
}

function Test-PwrPackage($Pkg) {
	$PkgPath = Resolve-PwrPackage $Pkg
	return Test-Path "$PkgPath\.pwr"
}

function Invoke-PwrPackagePull($Pkg, [ref]$Job) {
	if (Test-PwrPackage $Pkg) {
		Write-PwrFatal "cannot fetch $($Pkg.Ref) when already exists"
	} elseif ($Offline) {
		Write-PwrFatal "cannot fetch $($Pkg.Ref) while running offline"
	} else {
		Write-PwrOutput "fetching $($Pkg.Ref)"
		$Manifest = Get-ImageManifest $Pkg
		$PkgPath = Resolve-PwrPackage $Pkg
		mkdir $PkgPath -Force | Out-Null
		foreach ($Layer in $Manifest.Layers) {
			if ($Layer.MediaType -eq 'application/vnd.docker.image.rootfs.diff.tar.gzip') {
				$Job.Value += Invoke-PullImageLayer $PkgPath $Pkg.Ref $Pkg.Repo $Layer.Digest
			}
		}
	}
}

function Receive-PwrJob($Job, $Pkgs) {
	if ($Job.Count -gt 0) {
		Receive-Job -Job $Job -Wait
		foreach ($J in $Job) {
			if ($J.State -eq 'Failed') {
				Remove-Job $Job
				Write-PwrFatal 'one or more jobs failed'
			}
		}
		Remove-Job $Job
		Write-PwrOutput "fetched $($Pkgs.Count) package$(if ($Pkgs.Count -ne 1) { 's' }) ($($Refs = foreach ($P in $Pkgs) { $P.Ref }; $Refs -join ', '))"
	}
}

function Invoke-PwrPackageShell($Pkg) {
	$PkgPath = Resolve-PwrPackage $Pkg
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
		Write-PwrInfo "using config at $PwrConfigPath"
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
	Get-ChildItem -Path $PwrPkgPath -ErrorAction SilentlyContinue | ForEach-Object {
		if ($_.Name -match '(.+)-([0-9].+)') {
			$Pkg = $Matches[1]
			$Ver = $Matches[2]
			$Pkgs.$Pkg = @($Pkgs.$Pkg) + @([SemanticVersion]::new($Ver)) | Sort-Object -Descending
		}
	}
	return $Pkgs
}

function Select-PwrPackages([parameter(ValueFromPipeline=$True)]$Pkgs) {
	if (-not $Packages) {
		return $Pkgs
	}
	$Out = @{}
	foreach ($Pkg in $Pkgs.Keys) {
		foreach ($Ver in $Pkgs.$Pkg) {
			if ($Packages | Where-Object { ($_ -match '^([^:]+):?(.*)$') -and ($Pkg -eq $Matches[1] -and (-not $Matches[2] -or $Ver -match "^$([regex]::Escape($Matches[2]))(?:[^0-9]|$)")) } ) {
				$Out.$Pkg = @($Out.$Pkg) + @([SemanticVersion]::new($Ver)) | Sort-Object -Descending
			}
		}
	}
	return $Out
}

function Format-PwrPackages([parameter(ValueFromPipeline=$True)]$Packages) {
	''
	$Packages | Format-List | Out-String -Stream | Where-Object{ $_.Length -gt 0 } | Sort-Object
	''
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
			Write-PwrInfo "overriding $P with $Over"
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
	if ($env:PwrShellPackages) {
		Write-PwrFatal "cannot start a new shell session while one is in progress; use command 'exit' to end the current session"
	}
	Assert-NonEmptyPwrPackages
	Lock-PwrLock
	try {
		$LoadCache = Get-PwrLoadCache
		$Job = $Pkgs = $PwrPkgs = @()
		foreach ($P in $Packages) {
			$Pkg = Assert-PwrPackage $P
			if (-not (Test-PwrPackage $Pkg)) {
				Invoke-PwrPackagePull $Pkg ([ref]$Job)
				$Pkgs += , $Pkg
			}
			$PwrPkgs += , $Pkg
			Set-PwrLoadCache $LoadCache $Pkg.Id $Pkg.Tag
		}
		Receive-PwrJob $Job $Pkgs
		Save-PwrLoadCache $LoadCache
		Save-PSSessionState
		$env:PwrShellPackages = "$($Refs = foreach ($P in $PwrPkgs) { $P.Ref }; $Refs -join ' ')"
		Clear-PSSessionState
		foreach ($P in $PwrPkgs) {
			try {
				Invoke-PwrPackageShell $P
			} catch {
				Restore-PSSessionState
				$env:PwrShellPackages = $null
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
	$env:Path = "$(if ($env:Path.Length -gt 0) { "$env:Path;" })$env:SYSTEMROOT;$env:SYSTEMROOT\System32;$env:SYSTEMROOT\System32\WindowsPowerShell\v1.0"
}

function Exit-Shell {
	if ($env:PwrShellPackages) {
		Restore-PSSessionState
		$env:PwrShellPackages = $null
		Write-PwrDebug 'shell session closed'
	} else {
		Write-PwrFatal 'no shell session is in progress'
	}
}

function Invoke-PwrScriptCommand($Script) {
	if ($Script -is [PSCustomObject]) {
		$Format = $Script.Format
		if ($null -eq $Format) {
			$RunCmd = $Script.Command
			if ($null -eq $RunCmd) {
				Write-PwrFatal "missing JSON key, expected one of 'format' or 'command' in script '$Name'"
			} elseif ($RunCmd -isnot [string]) {
				Write-PwrFatal "wrong JSON type for value of 'command', expected string in script '$Name'"
			}
		} elseif ($Format -isnot [string]) {
			Write-PwrFatal "wrong JSON type for value of 'format', expected string in script '$Name'"
		} elseif ($null -ne $Script.Command) {
			Write-PwrFatal "cannot specify 'command' when 'format' is provided in script '$Name'"
		} else {
			$FormatArgs = @($Name)
			if ($Script.Args -is [Array]) {
				foreach ($A in $Script.Args) {
					if ($A -isnot [string]) {
						Write-PwrFatal "wrong JSON type for item of array 'args', expected string"
					}
					$FormatArgs += $A
				}
			} elseif ($null -ne $Script.Args) {
				Write-PwrFatal "wrong JSON type for value of 'args', expected array"
			}
			for ($I = 1; $I -lt $Run.Count; ++$I) {
				if ($I -lt $FormatArgs.Count) {
					$FormatArgs[$I] = $Run[$I]
				} else {
					$FormatArgs += $Run[$I]
				}
			}
			try {
				$RunCmd = [string]::Format($Format, [object[]]$FormatArgs)
			} catch {
				Write-PwrFatal "bad input [$($FormatArgs -join ', ')] for format '$Format', see below`n     $_"
			}
		}
		if ($null -ne $Script.Packages) {
			$script:Packages = $Script.Packages
		}
	} elseif ($Script -is [string]) {
		$RunCmd = $Script
	} elseif ($Run.Count -eq 1) {
		$RunCmd = $Run[0]
	} elseif ($Run.Count -gt 1) {
		$FormatArgs = @()
		for ($I = 1; $I -lt $Run.Count; ++$I) {
			$FormatArgs[$I - 1] = $Run[$I]
		}
		try {
			$RunCmd = [string]::Format($Run[0], [object[]]$FormatArgs)
		} catch {
			Write-PwrFatal "bad input [$($FormatArgs -join ', ')] for format '$($Run[0])', see below`n     $_"
		}
	} else {
		Write-PwrFatal "wrong JSON type for value of '$Name', expected string or object"
	}
	if ($env:PwrShellPackages) {
		Write-PwrFatal "cannot invoke script due to shell session already in progress"
	}
	try {
		Enter-Shell
	} catch {
		exit 1
	}
	$ScriptExitCode = $global:LASTEXITCODE = 0
	try {
		Invoke-Expression $RunCmd
		$ScriptExitCode = $global:LASTEXITCODE
	} catch {
		$ErrorMessage = $_.ToString().Trim()
	} finally {
		if ($env:PwrShellPackages) {
			Exit-Shell
		}
	}
	if ($ErrorMessage) {
		Write-PwrFatal "script '$Name' failed to execute command '$RunCmd'`n     $(foreach ($Line in $ErrorMessage.Split("`r`n")) { '>> ' + $Line })"
	} elseif ($ScriptExitCode -ne 0) {
		Write-PwrFatal "script '$Name' finished with non-zero exit value $ScriptExitCode`n     see output above for command '$RunCmd'"
	}
}

function Invoke-PwrScripts {
	if ($Packages.Count -gt 0) {
		if ($Run.Count -ne 1) {
			Write-PwrFatal "expected exactly one run argument: $Run"
		}
		Invoke-PwrScriptCommand @{Command = $Run[0]}
	} elseif ($PwrConfig) {
		$Name = $Run[0]
		$Script = $PwrConfig.Scripts.$Name
		if (($null -ne $Script) -or ($Run.Count -ge 1)) {
			$Location = Get-Location
			Set-Location (Split-Path $PwrConfigPath -Parent)
			try {
				Invoke-PwrScriptCommand $Script
			} finally {
				Set-Location $Location
			}
		} else {
			Write-PwrFatal "no declared script '$Name'"
		}
	} else {
		Write-PwrFatal 'no packages provided'
	}
}

function Get-PwrLoadCache {
	$LoadCacheFile = "$PwrPath\cache\load"
	Write-PwrDebug 'loading load cache'
	$LoadCache = @{
		LoadMap = @{}
		ObsoletePkgs = @{}
	}
	if (Test-Path -Path $LoadCacheFile -PathType Leaf) {
		try {
			$JsonObj = Get-Content $LoadCacheFile | ConvertFrom-Json
			foreach ($Load in $JsonObj.Loads) {
				$SplitAt = $Load.LastIndexOf(":")
				$LoadCache.LoadMap[$Load.Substring(0, $SplitAt)] = $Load.Substring($SplitAt + 1)
			}
			foreach ($ObsoletePkg in $JsonObj.ObsoletePkgs) {
				$SplitAt = $ObsoletePkg.LastIndexOf(":")
				$LoadCache.ObsoletePkgs[$ObsoletePkg.Substring(0, $SplitAt)] = $ObsoletePkg.Substring($SplitAt + 1)
			}
		} catch {
			Write-PwrFatal "bad JSON parse of file $LoadCacheFile - $_"
		}
	} else {
		$InstalledPkgs = Get-InstalledPwrPackages
		$InstalledPkgs.Keys | ForEach-Object {
			$LoadCache.LoadMap[$_] = "$_-$($InstalledPkgs.$_[0].ToString().Replace('+', '_'))"
		}
	}
	return $LoadCache
}

function Set-PwrLoadCache($LoadCache, $Id, $PkgTag) {
	if ($Id.StartsWith('file:///')) {
		return
	}
	$OldTag = $LoadCache.LoadMap[$Id]
	$LoadCache.LoadMap[$Id] = $PkgTag
	$LoadCache.ObsoletePkgs.Remove($PkgTag)
	if ($OldTag -and -not $LoadCache.LoadMap.ContainsValue($OldTag)) {
		$LoadCache.ObsoletePkgs[$OldTag] = Get-Date -Format FileDateTimeUniversal
		$EndOfName = $OldTag.LastIndexOf("-")
		Write-PwrOutput "package $($OldTag.Substring(0, $EndOfName)):$($OldTag.Substring($EndOfName + 1)) is eligible for pruning"
	}
}

function Save-PwrLoadCache {
	[CmdletBinding(SupportsShouldProcess)]
	param($LoadCache)
	$LoadCacheFile = "$PwrPath\cache\load"
	if ($PSCmdlet.ShouldProcess($LoadCacheFile, 'Save Load Cache')) {
		Write-PwrDebug 'saving load cache'
		mkdir (Split-Path $LoadCacheFile -Parent) -Force | Out-Null
		$JsonObj = @{
			Loads = @()
			ObsoletePkgs = @()
		}
		$LoadCache.LoadMap.GetEnumerator() | ForEach-Object {
			if (-not $_.Key.StartsWith('file:///')) {
				$JsonObj.Loads += "$($_.Key):$($_.Value)"
			}
		}
		$LoadCache.ObsoletePkgs.GetEnumerator() | ForEach-Object {
			$JsonObj.ObsoletePkgs += "$($_.Key):$($_.Value)"
		}
		[IO.File]::WriteAllText($LoadCacheFile, ($JsonObj | ConvertTo-Json -Compress))
	}
}

function PrunePwrPackages {
	[CmdletBinding(SupportsShouldProcess)]
	param($LoadCache, $ObsoleteDays)
	$TagsToKeep = $LoadCache.LoadMap.Values
	$ProcessedTags = @()
	$Pkgs = Get-InstalledPwrPackages
	$StalePkgs = @()
	foreach ($Name in $Pkgs.Keys) {
		foreach ($Ver in $Pkgs.$Name) {
			$Tag = "$Name-$($Ver.ToString().Replace('+', '_'))"
			$ProcessedTags += $Tag
			$PkgRoot = "$PwrPkgPath\$Tag"
			if ($Tag -NotIn $TagsToKeep) {
				# Check how long the tag has been obsolete, and remove it if beyond the number of days specified
				$ObsoleteDate = $LoadCache.ObsoletePkgs[$Tag]
				if (-not $ObsoleteDate) {
					$ObsoleteDate = Get-Date -Format FileDateTimeUniversal
					$LoadCache.ObsoletePkgs[$Tag] = $ObsoleteDate
				}
				if ((-not $ObsoleteDays -or [DateTime]::ParseExact($ObsoleteDate, 'yyyyMMddTHHmmssffffZ', $null) -lt ((Get-Date) - (New-TimeSpan -Days $ObsoleteDays))) -and $PSCmdlet.ShouldProcess($Tag, 'Prune pwr Tag')) {
					Write-PwrOutput "pruning ${Name}:$Ver ... " -NoNewline
					Remove-Directory "$PkgRoot"
					$LoadCache.ObsoletePkgs.Remove($Tag)
					Write-PwrHost 'done'
				}
			} else { # Check for stale packages (>= 180 days without use)
				try {
					$Item = Get-ChildItem -Path "$PkgRoot\.pwr" -ErrorAction Stop
					if ($Item.LastAccessTime -lt ((Get-Date) - (New-TimeSpan -Days 180))) {
						$StalePkgs += "${Name}:$Ver"
					}
				} catch {
					Write-PwrWarning "$PkgRoot is not a pwr package; it should be removed manually"
				}
			}
		}
	}
	if ($StalePkgs.Count -gt 0) {
		Write-PwrOutput "consider removing stale pwr packages: $($StalePkgs -join ', ')"
	}
	# Clean up load cache (non-existant packages will be removed from the maps)
	$OldLoadMap = $LoadCache.LoadMap
	$OldObsoletePkgs = $LoadCache.ObsoletePkgs
	$LoadCache.LoadMap = @{}
	$LoadCache.ObsoletePkgs = @{}
	foreach ($Id in $OldLoadMap.Keys) {
		if ($OldLoadMap[$Id] -In $ProcessedTags) {
			$LoadCache.LoadMap[$Id] = $OldLoadMap[$Id]
		}
	}
	foreach ($Tag in $OldObsoletePkgs.Keys) {
		if ($Tag -In $ProcessedTags) {
			$LoadCache.ObsoletePkgs[$Tag] = $OldObsoletePkgs[$Tag]
		}
	}
}

$ProgressPreference = 'SilentlyContinue'
$PwrPath = if ($env:PwrHome) { $env:PwrHome } else { "$env:AppData\pwr" }
$PwrPkgPath = "$PwrPath\pkg"
$env:PwrVersion = '0.5.1'
Write-PwrInfo "running version $env:PwrVersion with powershell $($PSVersionTable.PSVersion)"

if ($null -eq $Run) {
	switch ($Command) {
		{$_ -in 'v', 'version'} {
			if ($AssertMinimum) {
				$local:CurVer = [SemanticVersion]::new("$env:PwrVersion")
				$local:MinVer = [SemanticVersion]::new($AssertMinimum)
				if ($CurVer.CompareTo($MinVer) -lt 0) {
					Write-PwrFatal "$env:PwrVersion does not meet the minimum version $AssertMinimum"
				}
			} else {
				Write-PwrOutput "version $env:PwrVersion"
			}
			exit
		}
		'home' {
			Write-PwrHost $PwrPath
			exit
		}
		{$_ -in '', 'h', 'help'} {
			Get-Help $MyInvocation.MyCommand.Path -Detailed
			exit
		}
		'update' {
			if ($Offline) {
				Write-PwrFatal 'cannot update while running offline'
			} else {
				$CurrentVersion = [SemanticVersion]::new("$env:PwrVersion")
				$local:Tags = Invoke-PwrWebRequest 'https://api.github.com/repos/airpwr/airpwr/tags' | ConvertFrom-Json
				$local:Latest = [SemanticVersion]::new($local:Tags[0].Name.Substring(1))
				if ($local:Latest.LaterThan($CurrentVersion)) {
					if ((($CurrentVersion.Major -ne $local:Latest.Major) -or ($CurrentVersion.Minor -ne $local:Latest.Minor)) -and (-not $PSCmdlet.ShouldContinue($null, "Updating from pwr version $CurrentVersion to $local:Latest"))) {
						exit
					}
					$PwrCmd = "$PwrPath\cmd"
					$PwrScriptPath = "$PwrCmd\pwr.ps1"
					mkdir $PwrCmd -Force | Out-Null
					Invoke-PwrWebRequest "https://api.github.com/repos/airpwr/airpwr/contents/src/pwr.ps1?ref=v$local:Latest" | ConvertFrom-Json | ForEach-Object {
						$Content = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_.Content))
						[IO.File]::WriteAllText($PwrScriptPath, $Content)
					}
					$UserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
					if (-not $UserPath.Contains($PwrCmd)) {
						[Environment]::SetEnvironmentVariable('Path', "$UserPath;$PwrCmd", 'User')
					}
					if (-not "$env:Path".Contains($PwrCmd)) {
						$env:Path = "$env:Path;$PwrCmd"
					}
					$CacheDir = "$PwrPath\cache"
					Remove-Item $CacheDir -Recurse -Force | Out-Null
					$TagsCache = "$CacheDir\tags"
					mkdir (Split-Path $TagsCache -Parent) -Force | Out-Null
					[IO.File]::WriteAllText($TagsCache, ($local:Tags | ConvertTo-Json -Compress))
					$env:PwrVersion = $null
					& $PwrScriptPath | Out-Null
					Write-PwrOutput "version $env:PwrVersion sha256:$((Get-FileHash -Path $PwrScriptPath -Algorithm SHA256).Hash.ToLower())"
				} else {
					Write-PwrOutput "already running latest version $CurrentVersion"
				}
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
				Write-PwrFatal "bad JSON parse of file $PwrCfg - $_"
			}
		}
		$PwrCfgDir = Split-Path $PwrCfgDir -Parent
	} while ($PwrCfgDir.Length -gt 0)
}

function Lock-PwrLock {
	New-Item $PwrLock -ItemType File -WhatIf:$false -ErrorAction SilentlyContinue | Out-Null
	if (-not $?) {
		Write-PwrFatal "already fetching or removing package`n     if this isn't the case, manually delete $PwrLock"
	}
}

function Unlock-PwrLock {
	try {
		Remove-Item $PwrLock -WhatIf:$false
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

if ($null -ne $Run) {
	Invoke-PwrScripts
	exit
}

switch ($Command) {
	'fetch' {
		Assert-NonEmptyPwrPackages
		Lock-PwrLock
		try {
			$LoadCache = Get-PwrLoadCache
			$Job = $Pkgs = @()
			foreach ($P in $Packages) {
				$Pkg = Assert-PwrPackage $P
				if ($Pkg.Local) {
					Write-PwrFatal "tried to fetch local package $($Pkg.Ref)"
				} elseif (Test-PwrPackage $Pkg) {
					Write-PwrOutput "$($Pkg.Ref) already exists"
				} else {
					Invoke-PwrPackagePull $Pkg ([ref]$Job)
					$Pkgs += , $Pkg
				}
				Set-PwrLoadCache $LoadCache $Pkg.Id $Pkg.Tag
			}
			Receive-PwrJob $Job $Pkgs
			Save-PwrLoadCache $LoadCache
		} finally {
			Unlock-PwrLock
		}
	}
	'load' {
		Assert-NonEmptyPwrPackages
		Lock-PwrLock
		$_Path = $env:Path
		try {
			$env:Path = $null
			$LoadCache = Get-PwrLoadCache
			$Job = $Pkgs = $PwrPkgs = @()
			foreach ($P in $Packages) {
				$Pkg = Assert-PwrPackage $P
				if (-not (Test-PwrPackage $Pkg)) {
					Invoke-PwrPackagePull $Pkg ([ref]$Job)
					$Pkgs += , $Pkg
				}
				$PwrPkgs += , $Pkg
				Set-PwrLoadCache $LoadCache $Pkg.Id $Pkg.Tag
			}
			Receive-PwrJob $Job $Pkgs
			Save-PwrLoadCache $LoadCache
			foreach ($Pkg in $PwrPkgs) {
				if (-not "$env:PwrLoadedPackages".Contains($Pkg.Ref)) {
					Invoke-PwrPackageShell $Pkg
					$env:PwrLoadedPackages = "$($Pkg.Ref) $env:PwrLoadedPackages"
					Write-PwrOutput "loaded $($Pkg.Ref)"
				} elseif (Test-PwrPackage $Pkg) {
					Write-PwrOutput "$($Pkg.Ref) already loaded"
				}
			}
			$env:Path = "$env:Path;$_Path"
			$SetPath = $true
		} catch {
			exit 1
		} finally {
			if (-not $SetPath) {
				$env:Path = $_Path
			}
			Unlock-PwrLock
		}
	}
	{$_ -in 'sh', 'shell'} {
		try {
			Enter-Shell
		} catch {
			Write-PwrThrow $_
			exit 1
		}
	}
	'ls-config' {
		foreach ($P in $Packages) {
			$Pkg = Assert-PwrPackage $P
			if (-not (Test-PwrPackage $Pkg)) {
				Write-PwrFatal "package $($Pkg.Ref) is not installed"
			}
			$local:PkgPath = Resolve-PwrPackage $Pkg
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
			Write-PwrOutput "[$PwrPath]"
			$Show = Get-InstalledPwrPackages | Select-PwrPackages
			if ($Show.Count -eq 0) {
				Write-PwrHost '<none>'
			} else {
				New-Object PSObject -Property $Show | Format-PwrPackages
			}
		} else {
			foreach ($Repo in $PwrRepositories) {
				Write-PwrOutput "[$($Repo.Uri)]"
				$Show = $Repo.Packages | ConvertTo-HashTable | Select-PwrPackages
				if ($Show.Count -eq 0) {
					Write-PwrHost '<none>'
				} else {
					New-Object PSObject -Property $Show | Format-PwrPackages
				}
			}
		}
	}
	'prune' {
		if ($Packages.Count -gt 0) {
			Write-PwrFatal 'prune not compatible with -Packages'
		}
		Lock-PwrLock
		try {
			$LoadCache = Get-PwrLoadCache
			PrunePwrPackages $LoadCache
			Save-PwrLoadCache $LoadCache
		} finally {
			Unlock-PwrLock
		}
	}
	{$_ -in 'rm', 'remove'} {
		Lock-PwrLock
		try {
			if ($DaysOld) {
				Write-PwrWarning "-DaysOld is deprecated in favor of 'prune' and will be removed in a future version"
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
							Write-PwrHost 'done'
						}
					}
				}
			} else {
				Assert-NonEmptyPwrPackages
				foreach ($P in $Packages) {
					$Pkg = Assert-PwrPackage $P
					if ($Pkg.Local) {
						Write-PwrFatal "tried to remove local package $($Pkg.Ref)"
					} elseif ("$env:PwrLoadedPackages".Contains($Pkg.Ref)) {
						Write-PwrFatal "tried to remove loaded package $($Pkg.Ref)"
					} elseif ("$env:PwrShellPackages".Contains($Pkg.Ref)) {
						Write-PwrFatal "tried to remove shell session package $($Pkg.Ref)"
					} elseif (Test-PwrPackage $Pkg) {
						if ($PSCmdlet.ShouldProcess($Pkg.Ref, 'remove pwr package')) {
							Write-PwrOutput "removing $($Pkg.Ref) ... " -NoNewline
							$Path = Resolve-PwrPackage $Pkg
							Remove-Directory $Path
							Write-PwrHost 'done'
						}
					} else {
						Write-PwrFatal "$($Pkg.Ref) not found"
					}
				}
			}
		} finally {
			Unlock-PwrLock
		}
	}
	'which' {
		Assert-NonEmptyPwrPackages
		foreach ($local:P in $Packages) {
			$local:Pkg = Assert-PwrPackage $local:P
			Write-PwrHost "$($local:Pkg.Ref) $($local:Pkg.Digest)"
		}
	}
	'where' {
		Assert-NonEmptyPwrPackages
		foreach ($local:P in $Packages) {
			$local:Pkg = Assert-PwrPackage $local:P
			if (-not (Test-PwrPackage $local:Pkg)) {
				Write-PwrFatal "package $($local:Pkg.Ref) is not installed"
			}
			Write-PwrHost (Resolve-PwrPackage $local:Pkg)
		}
	}
	Default {
		Write-PwrFatal "no such command '$Command'"
	}
}
