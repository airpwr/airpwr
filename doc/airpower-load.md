# load

Loads packages into the PowerShell session.

A package exports one or more environment variables which are defined for the PowerShell session. If the package defines a `$env:Path` variable, it is prepended to the existing value.

An array of packages are accepted as input.

## Usage

	airpower load <package[:tag]>...

## Example

```
PS C:\example> airpower load somepkg
Digest: sha256:5987423d9c30b66bbce0ad10337a96bef2e49d69625a1647a769f4df4dc83172
Status: Session configured for somepkg:latest
```
