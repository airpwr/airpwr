. $PSScriptRoot\registry.ps1
. $PSScriptRoot\config.ps1
. $PSScriptRoot\progress.ps1
. $PSScriptRoot\log.ps1

function AsRemotePackage {
	param (
		[Parameter(
			Mandatory = $true,
			ValueFromPipeline = $true)]
		[string]$RegistryTag
	)
	if ($RegistryTag -match '(.*)-([0-9].+)') {
		return @{
			Package = $Matches[1]
			Tag = $Matches[2] | AsTag
		}
	}
	throw "failed to parse registry tag: $RegistryTag"
}

function AsTag {
	param (
		[Parameter(
			ValueFromPipeline = $true)]
		[string]$Tag
	)
	if ($Tag -in 'latest', '', $null) {
		return @{ Latest = $true }
	}
	if ($Tag -match '^([0-9]+)(?:\.([0-9]+))?(?:\.([0-9]+))?(?:(?:\+|_)([0-9]+))?$') {
		return @{
			Major = $Matches[1]
			Minor = $Matches[2]
			Patch = $Matches[3]
			Build = $Matches[4]
		}
	}
	throw "failed to parse tag: $Tag"
}

function SortTags {
	param (
		[object[]]$Tags
	)
	return $Tags | Sort-Object -Property {$_.Major}, {$_.Minor}, {$_.Patch}, {$_.Build} -Descending
}

function AsTagString {
	param (
		[Parameter(
			Mandatory = $true,
			ValueFromPipeline = $true)]
		[collections.Hashtable]$Tag
	)
	if ($true -eq $Tag.Latest) {
		"latest"
	} else {
		$s = "$($Tag.Major)"
		if ($Tag.Minor) {
			$s += ".$($Tag.Minor)"
		}
		if ($Tag.Patch) {
			$s += ".$($Tag.Patch)"
		}
		if ($Tag.Build) {
			$s += "+$($Tag.Build)"
		}
		$s
	}
}

function GetRemotePackages {
	$remote = @{}
	foreach ($tag in (GetTagsList).Tags) {
		$pkg = $tag | AsRemotePackage
		$remote.$($pkg.Package) = $remote.$($pkg.Package) + @($pkg.Tag)
	}
	$remote
}

function GetRemoteTags {
	$remote = GetRemotePackages
	$o = New-Object PSObject
	foreach ($k in $remote.keys | Sort-Object) {
		$arr = @()
		foreach ($t in $remote.$k) {
			$arr += [Tag]::new(($t | AsTagString))
		}
		$o | Add-Member -MemberType NoteProperty -Name $k -Value ($arr | Sort-Object -Descending)
	}
	$o
}

function AsPackage {
	param (
		[Parameter(
			Mandatory = $true,
			ValueFromPipeline = $true)]
		[string]$Pkg
	)
	if ($Pkg -match '^([^:]+)(?::([^:]+))?(?:::?([^:]+))?$') {
		return @{
			Package = $Matches[1]
			Tag = $Matches[2] | AsTag
			Config = if ($Matches[3]) { $Matches[3] } else { 'default' }
		}
	}
	throw "failed to parse package: $Pkg"
}

function ResolveRemoteRef {
	param (
		[Parameter(
			Mandatory = $true,
			ValueFromPipeline = $true)]
		[object]$Pkg
	)
	$remote = GetRemoteTags
	if (-not $remote.$($Pkg.Package)) {
		throw "no such package: $($Pkg.Package)"
	}
	$want = $Pkg.Tag
	foreach ($got in $remote.$($Pkg.Package)) {
		$eq = $true
		if ($null -ne $want.Major) {
			$eq = $eq -and $want.Major -eq $got.Major
		}
		if ($null -ne $want.Minor) {
			$eq = $eq -and $want.Minor -eq $got.Minor
		}
		if ($null -ne $want.Patch) {
			$eq = $eq -and $want.Patch -eq $got.Patch
		}
		if ($null -ne $want.Build) {
			$eq = $eq -and $want.Build -eq $got.Build
		}
		if ($eq) {
			return "$($Pkg.Package)-$(($got.ToString()).Replace('+', '_'))"
		}
	}
	throw "no such $($Pkg.Package) tag: $($Pkg.Tag)"
}

function GetLocalPackages {
	$db = GetPwrDB
	$pkgs = @()
	foreach ($pkg in $db.pkgdb.keys) {
		foreach ($tag in $db.pkgdb.$pkg.keys) {
			$t = [Tag]::new($tag)
			$digest = if ($t.None) { $tag } else { $db.pkgdb.$pkg.$tag }
			$pkgs += [PSCustomObject]@{
				Package = $pkg
				Tag = $t
				Digest = $digest | AsDigest
				Size = $db.metadatadb.$digest.size | AsSize
				# Signers
			}
		}
	}
	if (-not $pkgs) {
		$pkgs = ,[PSCustomObject]@{
			Package = $null
			Tag = $null
			Digest = $null
			Size = $null
		}
	}
	return $pkgs
}

function ResolvePackageDigest {
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[Collections.Hashtable]$Pkg
	)
	$db = GetPwrDB
	return $db.pkgdb.$($Pkg.Package).$($Pkg.Tag | AsTagString)
}

function InstallPackage { # $db, $status
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[Collections.Hashtable]$Pkg
	)
	$db = GetPwrDB
	$digest = $Pkg.Digest
	$name = $Pkg.Package
	$tag = $Pkg.Tag | AsTagString
	if ($null -ne $db.pkgdb.$name.$tag -and $digest -ne $db.pkgdb.$name.$tag) {
		$status = 'newer'
		$old = $db.pkgdb.$name.$tag
		$db.pkgdb.$name.Remove($tag)
		$db.pkgdb.$name.$old = $null
		if ($db.metadatadb.$old.refcount -gt 0) {
			$db.metadatadb.$old.refcount -= 1
		}
	}
	if ($null -eq $db.pkgdb.$name.$tag) {
		if ($db.metadatadb.$digest) {
			if ($db.pkgdb.$name.ContainsKey($digest)) {
				$db.pkgdb.$name.Remove($digest)
			}
			$status = 'tag'
			$db.metadatadb.$digest.refcount += 1
		} else {
			$status = 'new'
			$db.metadatadb.$digest = @{
				RefCount = 1
				Size = $Pkg.Size
			}
		}
		$db.pkgdb.$name += @{
			"$tag" = $digest
		}
	} else {
		$status = 'uptodate'
	}
	return $db, $status
}

function PullPackage {
	param (
		[Parameter(Mandatory,ValueFromPipeline)]
		[Collections.Hashtable]$Pkg
	)
	$manifest = $Pkg | ResolveRemoteRef | GetManifest
	$Pkg.Digest = $manifest | GetDigest
	$Pkg.Size = $manifest | GetSize
	WriteHost "$($pkg.Tag | AsTagString): Pulling $($Pkg.Package)"
	WriteHost "Digest: $($Pkg.Digest)"
	$db, $status = $Pkg | InstallPackage
	$ref = "$($Pkg.Package):$($Pkg.Tag | AsTagString)"
	if ($status -eq 'uptodate') {
		WriteHost "Status: Package is up to date for $ref"
	} else {
		if ($status -eq 'new') {
			$manifest | SavePackage
		}
		WriteHost "Status: Downloaded newer package for $ref"
		$db | OutPwrDB
	}
}

function SavePackage {
	param (
		[Parameter(Mandatory,ValueFromPipeline)]
		[Net.Http.HttpResponseMessage]$Resp
	)
	[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
	[Console]::CursorVisible = $false
	try {
		$manifest = $Resp | GetJsonResponse
		$digest = $Resp | GetDigest
		$tmp = @()
		foreach ($layer in $manifest.layers) {
			if ($layer.mediaType -eq 'application/vnd.docker.image.rootfs.diff.tar.gzip') {
				try {
					$tar = $layer.Digest | SaveBlob | DecompressTarGz
					$tar | ExtractTar -Digest $digest.Substring('sha256:'.Length)
					"$($layer.Digest.Substring('sha256:'.Length).Substring(0, 12)): Pull complete" + ' ' * 60 | WriteConsole
					$tmp += $tar, "$tar.gz"
				} finally {
					[Console]::WriteLine()
				}
			}
		}
		foreach ($file in $tmp) {
			[IO.File]::Delete($file)
		}
	} finally {
		[Console]::CursorVisible = $true
	}
}

function UninstallPackage { # $db, $digest, $err
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[Collections.Hashtable]$Pkg
	)
	$db = GetPwrDB
	$name = $Pkg.Package
	$key = $Pkg.Tag | AsTagString
	$table = $db.pkgdb.$name
	if (-not $db.pkgdb.ContainsKey($name) -or -not $table.ContainsKey($key)) {
		return $null, $null, "package not installed: ${name}:$key"
	}
	$digest = $table.$key
	$table.Remove($key)
	if ($table.Count -eq 0) {
		$db.pkgdb.Remove($name)
	}
	if ($db.metadatadb.$digest.refcount -gt 0) {
		$db.metadatadb.$digest.refcount -= 1
	}
	if (0 -eq $db.metadatadb.$digest.refcount) {
		$db.metadatadb.Remove($digest)
	} else {
		$digest = $null
	}
	return $db, $digest, $null
}

function RemovePackage {
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[Collections.Hashtable]$Pkg
	)
	$db, $digest, $err = $Pkg | UninstallPackage
	if ($null -ne $err) {
		throw $err
	}
	WriteHost "Untagged: $($Pkg.Package):$($pkg.Tag | AsTagString)"
	if ($null -ne $digest) {
		$content = $digest | ResolvePackagePath
		if (Test-Path $content -PathType Container) {
			[IO.Directory]::Delete($content, $true)
		}
		WriteHost "Deleted: $digest"
	}
	$db | OutPwrDB
}

function UninstallOrhpanedPackages {
	$db = GetPwrDB
	$rm = @()
	foreach ($digest in $db.metadatadb.keys) {
		$tbl = $db.metadatadb.$digest
		if ($tbl.refcount -eq 0) {
			$tbl.digest = $digest
			$rm += ,$tbl
		}
	}
	$empty = @()
	foreach ($i in $rm) {
		$db.metadatadb.Remove($i.digest)
		foreach ($pkg in $db.pkgdb.keys) {
			if ($db.pkgdb.$pkg.ContainsKey($i.digest)) {
				$db.pkgdb.$pkg.Remove($i.digest)
				if ($db.pkgdb.$pkg.Count -eq 0) {
					$empty += $pkg

				}
			}
		}
	}
	foreach ($name in $empty) {
		$db.pkgdb.Remove($name)
	}
	return $db, $rm
}

function PrunePackages {
	$db, $pruned = UninstallOrhpanedPackages
	$bytes = 0
	foreach ($i in $pruned) {
		$content = $i.Digest | ResolvePackagePath
		WriteHost "Deleted: $($i.Digest)"
		$stats = Get-ChildItem $content -Recurse | Measure-Object -Sum Length
		$bytes += $stats.Sum
		if (Test-Path $content -PathType Container) {
			[IO.Directory]::Delete($content, $true)
		}
	}
	WriteHost "Total reclaimed space: $($bytes | AsByteString)"
	$db | OutPwrDB
}

function ResolvePackagePath {
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[string]$Digest
	)
	return "$(GetPwrContentPath)\$($digest.Substring('sha256:'.Length))"
}

class Digest {
	[string]$Sha256

	Digest([string]$sha256) {
		$this.Sha256 = $sha256
	}

	[string] ToString() {
		return "$($this.Sha256.Substring('sha256:'.Length).Substring(0, 12))"
	}
}

function AsDigest {
	param (
		[Parameter(
			Mandatory = $true,
			ValueFromPipeline = $true)]
		[string]$Digest
	)
	return [Digest]::new($Digest)
}

class Tag : IComparable {
	[object]$Major
	[object]$Minor
	[object]$Patch
	[object]$Build
	hidden [bool]$None
	hidden [bool]$Latest

	Tag([string]$tag) {
		if ($tag -eq '<none>' -or $tag.StartsWith('sha256:')) {
			$this.None = $true
			return
		}
		if ($tag -in 'latest', '') {
			$this.Latest = $true
			return
		}
		if ($tag -match '^([0-9]+)(?:\.([0-9]+))?(?:\.([0-9]+))?(?:(?:\+|_)([0-9]+))?$') {
			$this.Major = $Matches[1]
			$this.Minor = $Matches[2]
			$this.Patch = $Matches[3]
			$this.Build = $Matches[4]
			return
		}
		throw "failed to parse tag: $tag"
	}

	[int] CompareTo([object]$Obj) {
		if ($Obj -isnot $this.GetType()) {
			throw "cannot compare types $($Obj.GetType()) and $($this.GetType())"
		}
		if ($this.Latest -or $Obj.Latest) {
			return $this.Latest - $Obj.Latest
		}
		if ($this.None -or $Obj.None) {
			return $Obj.None - $this.None
		}
		if ($this.Major -ne $Obj.Major) {
			return $this.Major - $Obj.Major
		} elseif ($this.Minor -ne $Obj.Minor) {
			return $this.Minor - $Obj.Minor
		} elseif ($this.Patch -ne $Obj.Patch) {
			return $this.Patch - $Obj.Patch
		} else {
			return $this.Build - $Obj.Build
		}
	}

	[string] ToString() {
		if ($this.None) {
			return ''
		}
		if ($null -eq $this.Major) {
			return 'latest'
		}
		$s = "$($this.Major)"
		if ($this.Minor) {
			$s += ".$($this.Minor)"
		}
		if ($this.Patch) {
			$s += ".$($this.Patch)"
		}
		if ($this.Build) {
			$s += "+$($this.Build)"
		}
		return $s
	}
}

function ResolvePackage {
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[string]$Ref
	)
	$pkg = $Ref | AsPackage
	$digest = $pkg | ResolvePackageDigest
	switch (GetPwrPullPolicy) {
		'IfNotPresent' {
			if (-not $digest) {
				$pkg | PullPackage | Out-Null
				$pkg.digest = $pkg | ResolvePackageDigest
			}
		}
		'Never' {
			if (-not $digest) {
				throw "cannot find package $($pkg.Package):$($pkg.Tag | AsTagString)"
			}
		}
		'Always' {
			$pkg | PullPackage | Out-Null
			$pkg.digest = $pkg | ResolvePackageDigest
		}
		default {
			throw "invalid PwrPullPolicy '$(GetPwrPullPolicy)'"
		}
	}
	return $pkg
}
