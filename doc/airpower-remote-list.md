# remote list

Outputs an object of remote packages and versions.

## Usage

	airpower remote list

## Examples

```
PS C:\example> airpower remote list

somepkg    : {1.2.3, 1.1.0}
anotherpkg : 3.3.1
```

```
PS C:\example> airpower remote list | select -expand somepkg

Major Minor Patch Build
----- ----- ----- -----
1     2     3
1     1     0
```
