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
[`exec`](#) | Runs a user-defined scriptblock in a managed PowerShell session
[`run`](#) | Runs a user-defined scriptblock provided in a project file
[`prune`](./doc/airpower-prune.md) | Deletes unreferenced packages
[`remove`](./doc/airpower-remove.md) | Untags and deletes packages
[`help`](./doc/airpower-help.md) | Outputs usage for this command