# save

Downloads packages for use in an offline installation.

Packages are pulled and saved locally in the specified output directory.

An array of packages are accepted as input.

## Usage

	airpower save <package>[:tag]... <output directory>

## Example

```
PS C:\example> airpower save somepkg airpower-cache
Pulling somepkg:latest
Digest: sha256:db2a58b317e90e537aa1e9b9ab4f1875689bcd9d25a20abdfbf96d3cb0a5ec45
d47df44424b8: Pull complete
```
