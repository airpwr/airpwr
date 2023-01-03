# Airpower

A package manager and environment to provide consistent tooling for software teams.

`Airpower`, or `pwr`, manages software packages using container technology and allows users to configure local PowerShell sessions to their need. A standardized project script integrates seamlessly with `pwr` providing common packages and build commands spec which can be kept in source control for consistency across environments.

# Requirements

Windows operating system with PowerShell version 5.1 or later.

# Installing

In a PowerShell window, run the following command.

```PowerShell
Install-Module Airpower -Scope CurrentUser
```

See the [PS Gallery](https://www.powershellgallery.com/packages/Airpower) for other installation methods.

# pwr

The base command of the Airpower CLI.

## Child commands
Command | Description
--|--
[`pwr version`](#) | Outputs the version of the module
[`pwr list`](#) | Outputs a list of installed packages
[`pwr remote`](#) | Outputs an object of remote packages and versions
[`pwr pull`](#) | Downloads packages
[`pwr load`](#) | Loads packages into the PowerShell session
[`pwr exec`](#) | Runs a user-defined scriptblock in a managed PowerShell session
[`pwr run`](#) | Runs a user-defined scriptblock provided in a project file
[`pwr prune`](#) | Deletes unreferenced packages
[`pwr remove`](#) | Untags and deletes packages