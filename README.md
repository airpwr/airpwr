# airpwr

A package manager and environment to provide consistent tooling for software teams.

`pwr` provides declarative development environments to teams when traditional isolation and virtualization technologies cannot be employed. Calling `pwr shell` configures a consistent, local shell with the needed tools used to build and run software. This empowers teams to maintain consistentency in their build process and track configuration in version control systems (CaC).

# Installing

## Powershell (recommended)

Open a powershell terminal and execute the following command:

	iex (iwr 'https://raw.githubusercontent.com/airpwr/airpwr/main/src/install.ps1')

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

`pwr` can be configured entirely through the command line syntax; however, for convenience and to enable *Configuration as Code*, a local file the the current directory, named `pwr.json`, is supported.

A `pwr.json` might look like:

```json
{
    "packages": [
        "java:8",
        "python"
    ],
    "repositories": [
        "airpower/shipyard",
        "example.com/registry/v2/my/repo"
    ]
}
```
# Usage

	SYNTAX
	pwr [[-Command] <String>] [[-Packages] <String[]>] [-Repositories <String[]>] [-Fetch] [<CommonParameters>]

	PARAMETERS
	 -Command <String>
		list, ls                Displays all packages and their versions
		fetch                   Downloads packages
		shell, sh               Configures the current shell for the given package list and starts a session
		exit                    Exits the shell session and restores the pevious state
		help, h                 Displays syntax and descriptive information for calling pwr
		version, v              Displays this verion of pwr
		remove, rm              Removes package data from the local machine
		update                  Updates the pwr command to the latest version

	-Packages <String[]>
		A list of packages and their versions to be used in the fetch or shell command
		Must be in the form name[:version]
		  - When the version is omitted, the latest available is used
		  - Version must be in the form [Major[.Minor[.Patch]]] or 'latest'
		  - If the Minor or Patch is omitted, the latest available is used
			(e.g. pkg:7 will select the latest version with Major version 7)
		When this parameter is omitted, packges are read from a file named 'pwr.json' in the current working directory
		  - The file must have the form { "packages": ["pkg:7", ... ] }

	-Repositories <String[]>
		A list of OCI compliant container repositories
		When this parameter is omitted and a file named 'pwr.json' exists the current working directory, repositories are read from that file
		  - The file must have the form { "repositories": ["example.com/v2/some/repo"] }
		  - The registry (e.g. 'example.com/v2/') may be omitted when the registry is DockerHub
		When this parameter is omitted and no file is present, a default repository is used

		In some cases, you will need to add authentication for custom repositories
		  - A file located at '%appdata%\pwr\auths.json' is read
		  - The file must have the form { "<repo url>": { "basic": "<base64>" }, ... }

	-Fetch [<SwitchParameter>]
		Forces the repository of packges to be synchronized from the upstream source
		Otherwise, the cached repository is used and updated if older than one day

## Examples

Configuring a development shell

	pwr shell java, gradle, python

Listing available packages

	pwr list
