# remove

Untags and deletes packages.

The provided tag is first removed. Then, if the package has no remaining tags referring to its digest, the package is deleted.

An array of package are accepted as input.

## Usage

	airpower <remove | rm> <package[:tag]>...

## Example

```
PS C:\example> airpower remove somepkg
Untagged: somepkg:latest
Deleted: sha256:db2a58b317e90e537aa1e9b9ab4f1875689bcd9d25a20abdfbf96d3cb0a5ec45
```
