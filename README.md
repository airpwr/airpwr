# Airpower

A package manager and environment to provide consistent tooling for software teams.

Airpower manages software packages using container technology and allows users to configure local PowerShell sessions to their need. Airpower seamlessly integrates common packages with a standardized project script to enable common build commands kept in source control for consistency.

# Requirements

Windows operating system with PowerShell version 5.1 or later.

# Installing

Use this PowerShell command to install Airpower:

```PowerShell
Install-Module Airpower -Scope CurrentUser
```

When you want to avoid user prompts, use these PowerShell commands before installation:

```PowerShell
Install-PackageProvider -Name NuGet -Force
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
```

See the [Airpower PS Gallery](https://www.powershellgallery.com/packages/Airpower) for other installation methods.

# Updating

Use this PowerShell command to update Airpower:

```PowerShell
Update-Module Airpower
```

# Usage

Airpower is provided by the `Invoke-Airpower` commandlet. Several aliases are provided for ease-of-use: `airpower`, `air`, and `pwr`.

	airpower [COMMAND]

## Commands

Command | Description
-- | --
[`version`](./doc/airpower-version.md) | Outputs the version of the module
[`list`](./doc/airpower-list.md) | Outputs a list of installed packages
[`remote`](./doc/airpower-remote.md) | Outputs the remote
[`remote list`](./doc/airpower-remote-list.md) | Outputs information about the remote an object of remote packages and versions
[`remote set`](./doc/airpower-remote-set.md) | Sets the remote
[`pull`](./doc/airpower-pull.md) | Downloads packages
[`load`](./doc/airpower-load.md) | Loads packages into the PowerShell session
[`exec`](./doc/airpower-exec.md) | Runs a user-defined scriptblock in a managed PowerShell session
[`run`](./doc/airpower-run.md) | Runs a user-defined scriptblock provided in a project file
[`update`](./doc/airpower-update.md) | Updates all tagged packages
[`prune`](./doc/airpower-prune.md) | Deletes unreferenced packages
[`remove`](./doc/airpower-remove.md) | Untags and deletes packages
[`help`](./doc/airpower-help.md) | Outputs usage for this command

# Configuration

## Global

The following variables modify runtime behavior of `airpower`. Each can be specified as an in-scope variable or an environment variable.

### `AirpowerPullPolicy`

The pull policy determines when a package is downloaded, or pulled, from the upstream registry. It is a `[string]` which can take on the values:

- `"IfNotPresent"` - The package is pulled only when its tag does not exist locally.
- `"Never"` - The package is never pulled. If the tag does not exist, an error is raised.
- `"Always"` - The package is pulled from the upstream registry. If the local tag matches the remote digest, no data is downloaded.

> The default `AirpowerPullPolicy` is `"IfNotPresent"`.

### `AirpowerPath`

The path determines where packages and metadata exist on a user's machine. It is a `[string]`.

> The default `AirpowerPath` is `"$env:LocalAppData\Airpower"`.

### `AirpowerRemote`

The remote determines where packages are pulled from. This variable takes precedence over the `airpower remote set` command. It is a `[string]`.

> The default `AirpowerRemote` is `"dockerhub"`.

### `AirpowerAutoupdate`

The autoupdate determines if and how often the [update](./doc/airpower-update.md) action is taken. It is a [`[timespan]`](https://learn.microsoft.com/en-us/dotnet/api/system.timespan) but can be specified and parsed as a `[string]`. The autoupdate mechanism is evaluated upon initialization of the `airpower` module, meaning once per shell instance in which you use an `airpower` command.

For example, if `AirpowerAutoupdate` is set to `'1.00:00:00'`, then update will only automatically execute for packages that were last updated at least one day ago.

> The default `AirpowerAutoupdate` is `$null`

### `AirpowerAutoprune`

The autoprune determines if and how often the [prune](./doc/airpower-prune.md) action is taken. It is a [`[timespan]`](https://learn.microsoft.com/en-us/dotnet/api/system.timespan) but can be specified and parsed as a `[string]`. The autoprune mechanism is evaluated upon initialization of the `airpower` module, meaning once per shell instance in which you use an `airpower` command.

For example, if `AirpowerAutoprune` is set to `'1.00:00:00'`, then prune will only automatically execute for packages that have been orphaned for at least one day.

> The default `AirpowerAutoprune` is `$null`.

## Custom Packages

Custom packages can be sourced from either the internet or your computer. Declare a custom package with the functions:

- `AirpowerPackage<PackageName>Digest`
    - Parameters: `[string]` tag name
    - Output: `[string]` tag, `[string]` sha256 digest
- `AirpowerPackage<PackageName>Download`
    - Parameters: `[string]` tag, `[string]` sha256 digest, `[string]` output directory
    - Output: `[long]` bytes downloaded, `[string[]]` optional list of files to include on the path

All parameters and outputs are required except as noted otherwise.

For example, to create a new package called `SomePkg`, define the following functions:

```ps1
function AirpowerPackageSomePkgDigest {
	param (
		[Parameter(Mandatory)]
		[string]$TagName
	)
	@{
		'latest' = @('1.2.3', '80c1727245fd65a95ec6a3b9d80f7f8151d7ea7d6e31f1b98d63b1c2e1bf3a6c')
		'1.2.3' = @('1.2.3', '80c1727245fd65a95ec6a3b9d80f7f8151d7ea7d6e31f1b98d63b1c2e1bf3a6c')
		'1.2.2' = @('1.2.2', '1306bdb24529aa4f14d23f77604f7c5965c9d8cc9bbd2eda1ae3adecc251e18d')
	}[$TagName]
}

function AirpowerPackageSomePkgDownload {
	param (
		[Parameter(Mandatory)]
		[string]$Tag,
		[Parameter(Mandatory)]
		[string]$Digest,
		[Parameter(Mandatory)]
		[string]$Path
	)
	$file = "path\to\SomePkg-$Tag-$Digest.zip"
	Expand-Archive -Path $file -DestinationPath $Path
	(Get-Item $file).Length, @('somepkg.exe')
}
```

## Custom Registries

Custom registries can be declared similarly to custom packages, with the following functions:

- `AirpowerResolve<RegistryName>Tags`
    - Parameters: none
    - Output: `[hashtable]` of key `[string]` as package names and value `[string[]]` as a list of tags
- `AirpowerResolve<RegistryName>Digest`
    - Parameters: `[string]` package name, `[string]` tag name
    - Output: `[string]` tag, `[string]` sha256 digest
- `AirpowerResolve<RegistryName>Download`
    - Parameters: `[string]` package name, `[string]` tag, `[string]` sha256 digest, `[string]` output directory
    - Output: `[long]` bytes downloaded, `[string[]]` optional list of files to include on the path

All parameters and outputs are required except as noted otherwise.

For example, to create a new registry called `Custom`, define the following functions:

```ps1
function AirpowerResolveCustomTags {
	[hashtable]@{
		'package1' = @('1.2.3', '2.3.4')
		'package2' = @('1.0', '4.5.0.1')
	}
}

function AirpowerResolveCustomDigest {
	param (
		[Parameter(Mandatory)]
		[string]$Package,
		[Parameter(Mandatory)]
		[string]$TagName
	)
	@{
		'package1' = @{
			'1.2.3' = @('1.2.3', '34ed1b3bdc3ea41000f5c71393e74c4363efb63c0084d4b32a19cae0a3559d0b')
			'latest' = @('2.3.4', '34c18a5003e102cf171b9889528d2fe2eac23778564e45c426f06e53b7852784')
			'2.3.4' = @('2.3.4', '34c18a5003e102cf171b9889528d2fe2eac23778564e45c426f06e53b7852784')
		}
		'package2' = @{
			'1.0' = @('1.0', '3f5c85706a357401ee29c8ed79155702f25ac40d2bad82590695190a5e5d4001')
			'4.5.0.1' = @('4.5.0.1', '1151b1949d965201bab2d1ffc1963dd40f98d234a59d2b60e864af0936520fc6')
			'latest' = @('4.5.0.1', '1151b1949d965201bab2d1ffc1963dd40f98d234a59d2b60e864af0936520fc6')
		}
	}[$Package][$TagName]
}

function AirpowerResolveCustomDownload {
	param (
		[Parameter(Mandatory)]
		[string]$Package,
		[Parameter(Mandatory)]
		[string]$Tag,
		[Parameter(Mandatory)]
		[string]$Digest,
		[Parameter(Mandatory)]
		[string]$Path
	)
	$file = "$env:Temp\$Package-$Tag-$Digest.zip"
	Invoke-WebRequest -Uri "https://example.com/$Package/v$Tag/$Package.zip" -UseBasicParsing -OutFile $file
	try {
		Expand-Archive -Path $file -DestinationPath $Path
		(Get-Item $file).Length, @("$Package.exe")
	} finally {
		Remove-Item $file
	}
}
```

## Other

### `ProgressPreference`

The progress bar for downloading and extracting packages can be suppressed by assigning the `ProgressPreference` variable to `'SilentlyContinue'`. This behavior is often desirable for environments such as CI pipelines.