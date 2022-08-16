# airpwr

A package manager and environment to provide consistent tooling for software teams.

`pwr` provides declarative development environments to teams when traditional isolation and virtualization technologies cannot be employed. Calling `pwr shell` configures a consistent, local shell with the needed tools used to build and run software. This empowers teams to maintain consistentency in their build process and track configuration in version control systems (CaC).

# Requirements

`pwr` requires the use of `C:\Windows\System32\tar.exe`, which is only availble on Windows builds greater than `17063`.

Use the following command in a `powershell` terminal to determine your build version.

	[Environment]::OSVersion.Version

# Installing

## Powershell (recommended)

Open a powershell terminal and execute the following command:

	iex (iwr 'https://raw.githubusercontent.com/airpwr/airpwr/main/src/install.ps1' -UseBasicParsing)

The installer downloads the `pwr` cmdlet and puts its location on the user path.

## Manually

Save the `pwr.ps1` cmdlet to a file on your machine (`$env:AppData\pwr\cmd` is recommended), and add that location to the `Path` environment variable.

# Authenticating to Container Registries

When a repository or registry needs authetication, `pwr` will look for an `auths.json` file located in `$env:AppData\pwr` to make web requests with the appropiate credentials.

> Note: Public repositories on Docker Hub do not need to be specified

An `auths.json` might look like:
```json
{
  "example.com/registry": {
    "basic": "<base64 string>"
  }
}
```

# Configuration

`pwr` can be configured entirely through the command line syntax; however, for convenience and to enable *Configuration as Code*, a file named `pwr.json` in the current or any parent directory is supported.

`pwr.json` file's contents might look like:

```json
{
  "packages": [
    "jdk:8",
    "python"
  ],
  "repositories": [
    "airpower/shipyard",
    "example.com/registry/v2/my/repo"
  ],
  "scripts": {
    "name": "command"
  }
}
```

## Environment Variables
| Name | Default Value | Description |
|--|--|--|
| `PwrHome` | `$env:AppData\pwr` | The location `pwr` uses for package storage and other data caching. |

# Usage

SYNTAX
	pwr [[-Command] <String>] [[-Packages] <String[]>] [-Repositories <String[]>] [-Fetch] [-Installed] [-AssertMinimum <String>] [-DaysOld <Int32>] [-Offline] [-Quiet] [-Silent] [-Override] [-Run <String>] [-WhatIf]

PARAMETERS
	-Command <String>
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

	-Packages <String[]>
		A list of packages and their versions to be used in the fetch or shell command
		Must be in the form name[:version][:configuration]
		  - When the version is omitted, the latest available is used
		  - Version must be in the form [Major[.Minor[.Patch]]] or 'latest'
		  - If the Minor or Patch is omitted, the latest available is used
			(e.g. pkg:7 will select the latest version with Major version 7)
		  - When the configuration is omitted, the default used
		When this parameter is omitted, packages are read from a file named 'pwr.json' in the current or any parent directories
		  - The file must have the form { "packages": ["pkg:7", ... ] }

	-Repositories <String[]>
		A list of OCI compliant container repositories
		When this parameter is omitted and a file named 'pwr.json' exists in the current or any parent directories, repositories are read from that file
		  - The file must have the form { "repositories": ["example.com/v2/some/repo"] }
		  - The registry (e.g. 'example.com/v2/') may be omitted when the registry is DockerHub
		When this parameter is omitted and no file is present, a default repository is used

		In some cases, you will need to add authentication for custom repositories
		  - A file located at '%appdata%\pwr\auths.json' is read
		  - The file must have the form { "<repo url>": { "basic": "<base64>" }, ... }

	-Fetch [<SwitchParameter>]
		Forces the repository of packages to be synchronized from the upstream source
		Otherwise, the cached repository is used and updated if older than one day

	-Offline [<SwitchParameter>]
		Prevents attempts to request a web resource

	-Quiet [<SwitchParameter>]
		Suppresses all output to stdout

	-Silent [<SwitchParameter>]
		Suppresses all output to stdout and stderr

	-AssertMinimum <String>
		Writes an error if the provided semantic version (a.b.c) is not met by this scripts version
		Must be called with the `version` command

	-Override [<SwitchParameter>]
		Overrides 'pwr.json' package versions with the versions provided by the `Packages` parameter
		The package must be declared in the configuration file
		The package must not be expressed by a file URI

	-DaysOld <Int32>
		Use with the `remove` command to delete packages that have not been used within the specified period of days
		When this parameter is used, `Packages` must be empty

	-Installed [<SwitchParameter>]
		Use with the `list` command to enumerate the packages installed on the local machine

	-WhatIf [<SwitchParameter>]
		Use with the `remove` command to show the dry-run of packages to remove

	-Run <String>
		Executes the user-defined script inside a shell session
		The script is declared like { ..., "scripts": { "name": "something to run" } } in 'pwr.json'
		Additional arguments are passed to the script when the value of this parameter includes the delimiter "--" with subsequent text
		Scripts support pre and post actions when accompanying keys "pre<name>" or "post<name>" exist

## Examples

Configuring a development shell

	pwr shell jdk:8, gradle, python

Listing available packages

	pwr list
