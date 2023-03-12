# list

Outputs a list of installed packages.

When a displayed package has an empty tag, it is considered *orphaned* and eligible to be pruned via the `prune` command.

## Usage

	airpower list

## Examples

```
PS C:\example> airpower list

Package    Tag    Digest       Size
-------    ---    ------       ----
somepkg    1      e39f16178524 193.25 MB
anotherpkg latest 9e662865b2ba 349.89 MB
```

```
PS C:\example> airpower list | where { $_.Package -eq 'somepkg' } | select -expand digest

Sha256
------
sha256:e39f16178524d44ac5ca5323afe09f05b3af2fe28a070ca307f99eb8369535d6
```
