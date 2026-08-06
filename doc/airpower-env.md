# env

Modifies the environment variables provided by packages.

## Usage

	airpower env add <package>[:tag]... [process|user|machine]

	airpower env remove <package>[:tag]... [process|user|machine]

## Example

```
PS C:\example> airpower env add git
Package: git@sha256:88fea7c46969da2d72da21bd9725b80946ee71bdcc8c60e4daf6920f0e13aaa3
Added: \git\cmd \git\usr\bin \git\mingw64\bin
```

```
PS C:\example> airpower env remove git
Package: git@sha256:88fea7c46969da2d72da21bd9725b80946ee71bdcc8c60e4daf6920f0e13aaa3
Removed: \git\cmd \git\usr\bin \git\mingw64\bin
```
