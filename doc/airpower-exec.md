# exec

Runs a user-defined scriptblock in a managed PowerShell session.

## Usage

    airpower exec <package[:tag]>... [script block]

## Example

```
PS C:\example> airpower exec go { go version }

go version go1.20.2 windows/amd64
```
