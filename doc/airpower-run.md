# run

Runs a user-defined scriptblock provided in a project file.

## Usage

    airpower run <script>

## Example

```PowerShell
# .\Airpower.ps1

function AirpowerPrint {
	"Hello world!"
}
```

```
PS C:\example> airpower run print
Hello world!
```
