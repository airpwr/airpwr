# Airpower

A package manager and environment to provide consistent tooling for software teams.

Airpower manages software packages using container technology and allows users to configure local PowerShell sessions to their need. Airpower seamlessly integrates common packages with a standardized project script for providing build commands which can be kept in source control for consistency across environments.

# Requirements

Windows operating system with PowerShell version 5.1 or later.

# Installing

To install Airpower, use the PowerShell command:

```PowerShell
Install-Module Airpower -Scope CurrentUser
```

Or, to avoid user prompts (such as continuous integration environments), use the PowerShell commands:

```PowerShell
Install-PackageProvider -Name NuGet -Force
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-Module Airpower -Scope CurrentUser
```

See the [Airpower PS Gallery](https://www.powershellgallery.com/packages/Airpower) for other installation methods.

# Usage

The base command of Airpower is `Invoke-Airpower`. Several aliases are provided for ease-of-use: `airpower`, `air`, and `pwr`.

## Child commands

Command | Description
-- | --
[`airpower version`](#) | Outputs the version of the module
[`airpower list`](#) | Outputs a list of installed packages
[`airpower remote`](#) | Outputs an object of remote packages and versions
[`airpower pull`](#) | Downloads packages
[`airpower load`](#) | Loads packages into the PowerShell session
[`airpower exec`](#) | Runs a user-defined scriptblock in a managed PowerShell session
[`airpower run`](#) | Runs a user-defined scriptblock provided in a project file
[`airpower prune`](#) | Deletes unreferenced packages
[`airpower remove`](#) | Untags and deletes packages