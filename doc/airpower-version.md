# version

Outputs the in-use version of the module.

## Usage

	airpower [version | v]

## Examples

```
PS C:\example> airpower version

Major  Minor  Build  Revision
-----  -----  -----  --------
1      2      3      -1
```

```
PS C:\example> "I am using airpower version $(airpower v)"
I am using airpower version 1.2.3
```
