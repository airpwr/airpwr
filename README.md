# airpwr

A package manager to provide consistent tooling for software teams.

## Description

`pwr` enables configuration control for tools used to build and run software, allowing teams to maintain consistent, local environments when containerization technology cannot be employed.

## Installing

### Powershell (recommended)

Open a powershell terminal and execute the following command.
The installer downloads the `pwr` cmdlet and puts its location on the user path.

	iex (iwr 'https://raw.githubusercontent.com/airpwr/airpwr/main/src/install.ps1')

### Manually

Save the `pwr.ps1` cmdlet to a file on your machine and add that location to the `path` environment variable.
