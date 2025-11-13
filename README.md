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

Alternatively, if <powershellgallery.com> is not available, you can download or clone this repository and install locally with the `install.ps1` script.

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
[`remote`](./doc/airpower-remote.md) | Outputs an object of remote packages and versions
[`pull`](./doc/airpower-pull.md) | Downloads packages
[`load`](./doc/airpower-load.md) | Loads packages into the PowerShell session
[`exec`](./doc/airpower-exec.md) | Runs a user-defined scriptblock in a managed PowerShell session
[`run`](./doc/airpower-run.md) | Runs a user-defined scriptblock provided in a project file
[`update`](./doc/airpower-update.md) | Updates all tagged packages
[`prune`](./doc/airpower-prune.md) | Deletes unreferenced packages
[`remove`](./doc/airpower-remove.md) | Untags and deletes packages
[`save`](./doc/airpower-save.md) | Downloads packages for use in an offline installation
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

### `AirpowerAutoupdate`

The autoupdate determines if and how often the [update](./doc/airpower-update.md) action is taken. It is a [`[timespan]`](https://learn.microsoft.com/en-us/dotnet/api/system.timespan) but can be specified and parsed as a `[string]`. The autoupdate mechanism is evaluated upon initialization of the `airpower` module, meaning once per shell instance in which you use an `airpower` command.

For example, if `AirpowerAutoupdate` is set to `'1.00:00:00'`, then update will only automatically execute for packages that were last updated at least one day ago.

> The default `AirpowerAutoupdate` is `$null`

### `AirpowerAutoprune`

The autoprune determines if and how often the [prune](./doc/airpower-prune.md) action is taken. It is a [`[timespan]`](https://learn.microsoft.com/en-us/dotnet/api/system.timespan) but can be specified and parsed as a `[string]`. The autoprune mechanism is evaluated upon initialization of the `airpower` module, meaning once per shell instance in which you use an `airpower` command.

For example, if `AirpowerAutoprune` is set to `'1.00:00:00'`, then prune will only automatically execute for packages that have been orphaned for at least one day.

> The default `AirpowerAutoprune` is `$null`.

## Other

### `ProgressPreference`

The progress bar for downloading and extracting packages can be suppressed by assigning the `ProgressPreference` variable to `'SilentlyContinue'`. This behavior is often desirable for environments such as CI pipelines.