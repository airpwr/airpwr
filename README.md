# airpwr

A package manager and environment to provide consistent tooling for software teams.

`pwr` provides declarative development environments to teams when traditional isolation and virtualization technologies cannot be employed. Calling `pwr shell` configures a consistent, local shell with the needed tools used to build and run software. This empowers teams to maintain consistentency in their build process and track configuration in version control systems (CaC).

# Requirements

`pwr` requires the use of `$env:SystemDrive\Windows\System32\curl.exe` and `$env:SystemDrive\Windows\System32\tar.exe`, which are only available on Windows builds greater than `17063`.

Use the following command in a `powershell` terminal to determine your build version.

	[Environment]::OSVersion.Version

PowerShell version 5.0+ is required. Windows 10 and 11 have version 5.1 installed by default.

Use the following command in a `powershell` terminal to determine your PowerShell version.

	$PSVersionTable.PSVersion

# Installing

## PowerShell (recommended)

Open a `powershell` terminal and execute the following command:

	iex (& "$env:SYSTEMROOT\System32\curl.exe" -s --url 'https://raw.githubusercontent.com/airpwr/airpwr/main/src/install.ps1' | Out-String)

The installer downloads the `pwr` cmdlet and puts its location on the user path.

Run the `pwr` command afterwards to confirm that the installation was successful.

	pwr help

## Manually

Save the `pwr.ps1` cmdlet to a file on your machine (`$env:AppData\pwr\cmd` is recommended), and add that location to the `Path` environment variable.

# Configuration

`pwr` can be configured entirely through its command line syntax; however, for convenience and to enable *Configuration as Code*, a file named `pwr.json` in the current or any parent directory is supported.

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

For additional examples of the `scripts` object, see the [Example Scripts](#example-scripts) section.

## Environment Variables

Name | Default Value | Description
-- | -- | --
`PwrHome` | `$env:AppData\pwr` | The location `pwr` uses for package storage and other data caching.

# Authenticating to Container Registries

When a repository or registry needs authetication, `pwr` will look for an `auths.json` file located in `$env:PwrHome` to make web requests with the appropiate credentials.

> Note: Public repositories on Docker Hub do not need to be specified

An `auths.json` might look like:

```json
{
  "example.com/registry": {
    "basic": "<base64 string>"
  }
}
```

# Commands

## Prune

Removes all packages from `<pwr home>\pkg` that are out-of-date. Configure what packages should be considered "out-of-date" through the `<pwr home>\prune.json` file. As an example, the file might look like this:

```json
{
	"*": "latest",
	"jdk": "major",
	"jre": "major",
	"python": "minor"
}
```

The `prune.json` file describes the compatibility between different versions of the packages. For instance, `jdk:8` is not strictly compatible with `jdk:11`, whereas, `python:3.9` and `python:3.10` are not strictly compatible with each other. Other packages you might only want the latest version to be retained, e.g. `windows-terminal:latest`. Acceptable values are `latest`, `major`, `minor`, `patch`, and `build`. Using `build` for a package will disable pruning for that package. The wildcard `"*"` must be provided when any fetched package is not specified in `prune.json`, otherwise it may be omitted in cases where the user provides explicit rules for every package.

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
			home			Displays the pwr home path
			help, h			Displays syntax and descriptive information for calling pwr
			version, v		Displays this verion of pwr
			update			Updates the pwr command to the latest version
			remove, rm		Removes package data from the local machine
			prune			Removes out-of-date packages from the local machine
			which			Displays the package version and digest
			where			Displays the package install path

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

		-Info [<SwitchParameter>]
			Displays messages written to the information stream (6), otherwise the InformationPreference value is respected

		-Quiet [<SwitchParameter>]
			Suppresses messages written to the success stream (1), debug stream (5), and information stream (6)

		-Silent [<SwitchParameter>]
			Suppresses messages written to the success stream (1), error stream (2), warning stream (3), debug stream (5), and information stream (6)

		-AssertMinimum <String>
			Writes an error if the provided semantic version (a.b.c) is later than the pwr version
			Must be used in conjunction with the 'version' command

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
			The script is declared like `{ ..., "scripts": { "name": "something to run" } }` in 'pwr.json'
			To specify a script with parameters, declare it like `{ ..., "scripts": { "name": { "format": "something to run --arg={1}" } } }` in 'pwr.json'
			Arguments may be provided to the formatted script, referenced in the format as {1}, {2}, etc. ({0} refers to the script name)
			The format is interpreted by the string.Format method, with the values specified after the name of script
			Note: characters such as '{' and '}' need to be escaped by '{{' and '}}' respectively
			To specify a formatted script with default arguments, declare it like `{ ..., "scripts": { "name": { "format": "{0} {1}", "args": ["first"] } } }`
			These default arguments will be overridden by any value specified after the name of script, in the order provided

## Examples

Configuring a development shell

	pwr shell jdk:8, gradle, python

Listing available packages

	pwr list

### Example Scripts

The `scripts` object below declares three commands: `ls-path` prints out the current `Path` environment variable, `ls` executes the `ls -File` command (`{0}` is always the command name), and `git-log` accepts an optional parameter (`{1}`) that if not provided is set to `main`.

```json
{
	"script": {
		"ls-path": "$env:Path",
		"ls": {
			"format": "{0} -File"
		},
		"git-log": {
			"args": ["main"],
			"format": "git log {1}"
		}
	}
}
```
