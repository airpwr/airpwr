. $PSScriptRoot\config.ps1
. $PSScriptRoot\download.ps1
. $PSScriptRoot\progress.ps1
. $PSScriptRoot\log.ps1
. $PSScriptRoot\db.ps1
. $PSScriptRoot\pkg\all.ps1

function AsRemotePackage {
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[string]$RegistryTag
	)
	if ($RegistryTag -match '(.*)-([0-9].+)') {
		return @{
			Package = $Matches[1]
			Tag = if ($Matches[2] -in 'latest', '', $null) { 'latest' } else { $Matches[2] }
		}
	}
	throw "failed to parse registry tag: $RegistryTag"
}

function AsTagString {
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[string]$Tag
	)
	if ($Tag -ne 'latest') {
		$major, $minor, $build, $rev = AsVersion $Tag
		if ($major) {
			$s = $major
			if ($minor) {
				$s += ".$minor"
				if ($build) {
					$s += ".$build"
					if ($rev) {
						$s += ".$rev"
					}
				}
			}
			return $s
		}
	}
	$Tag
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
		[Parameter(Mandatory, ValueFromPipeline)]
		[string]$Pkg
	)
	if ($Pkg -match '^([^:]+)(?::([^:]+))?(?:::?([^:]+))?$') {
		return @{
			Package = $Matches[1]
			Tag = if ($Matches[2] -in 'latest', '', $null) { 'latest' } else { $Matches[2] }
			Config = if ($Matches[3]) { $Matches[3] } else { 'default' }
		}
	}
	throw "failed to parse package: $Pkg"
}

function ResolvePackageRefPath {
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[Collections.Hashtable]$Pkg
	)
	return "$(GetAirpowerPath)\ref\$($Pkg.Package)$(if ($Pkg.Tag -ne 'latest') { "-$($Pkg.Tag | AsTagString)" })"
}

function ResolveRemotePackage {
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[Collections.Hashtable]$Pkg
	)
	LoadConfig
	$fn = Get-Item "function:AirpowerPackage$($Pkg.Package)"
	if (-not $fn) {
		throw "no such package: $($Pkg.Package)"
	}
	$tag, $digest = & $fn $Pkg.Tag
	if ($tag -and $digest) {
		return $fn, $tag, $digest
	}
	throw "no such $($Pkg.Package) tag: $($Pkg.Tag)"
}

function GetLocalPackages {
	$pkgs = @()
	$locks, $err = [Db]::TryLockAll('pkgdb')
	if ($err) {
		throw $err
	}
	try {
		foreach ($lock in $locks) {
			$tag = $lock.Key[2]
			$t = [Tag]::new($tag)
			$digest = if ($t.None) { $tag } else { $lock.Get() }
			$m = [Db]::Get(('metadatadb', $digest))
			$pkgs += [LocalPackage]@{
				Package = $lock.Key[1]
				Tag = $t
				Digest = $digest | AsDigest
				Size = $m.size | AsSize
				Orphaned = if ($m.orphaned) { [datetime]::Parse($m.orphaned) }
			}
			$lock.Unlock()
		}
	} finally {
		if ($locks) {
			$locks.Revert()
		}
	}
	if (-not $pkgs) {
		$pkgs = ,[LocalPackage]@{}
	}
	return $pkgs
}

function ResolvePackageDigest {
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[Collections.Hashtable]$Pkg
	)
	if ($Pkg.Digest) {
		return $Pkg.Digest
	}
	$k = 'pkgdb', $Pkg.Package, ($Pkg.Tag | AsTagString)
	if ([Db]::ContainsKey($k)) {
		return [Db]::Get($k)
	}
}

function InstallPackage { # $locks, $status
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[Collections.Hashtable]$Pkg
	)
	$digest = $Pkg.Digest
	$name = $Pkg.Package
	$tag = $Pkg.Tag | AsTagString
	$locks = @()
	$mLock, $err = [Db]::TryLock(('metadatadb', $digest))
	if ($err) {
		throw "package '$digest' is in use by another airpower process"
	}
	$locks += $mLock
	$pLock, $err = [Db]::TryLock(('pkgdb', $name, $tag))
	if ($err) {
		$locks.Revert()
		throw "package '${name}:$tag' is in use by another airpower process"
	}
	$locks += $pLock
	$p = $pLock.Get()
	$m = $mLock.Get() | ConvertTo-HashTable
	$status = if ($null -eq $p) {
		if ($null -eq $m) {
			'new'
		} else {
			'tag'
		}
	} elseif ($digest -ne $p) {
		if ($null -eq $m) {
			'newer'
		} else {
			'ref'
		}
	} else {
		'uptodate'
	}
	$pLock.Put($digest)
	switch ($status) {
		{$_ -in 'new', 'newer'} {
			$mLock.Put(@{
				RefCount = 1
				Size = $Pkg.Size
			})
		}
		{$_ -in 'newer', 'ref'} {
			$moLock, $err = [Db]::TryLock(('metadatadb', $p))
			if ($err) {
				$locks.Revert()
				throw "package '$p' is in use by another airpower process"
			}
			$locks += $moLock
			$mo = $moLock.Get() | ConvertTo-HashTable
			$mo.RefCount -= 1
			if ($mo.RefCount -eq 0) {
				$poLock, $err = [Db]::TryLock(('pkgdb', $name, $p))
				if ($err) {
					$locks.Revert()
					throw "package '$p' is in use by another airpower process"
				}
				$locks += $poLock
				$poLock.Put($null)
				$mo.Orphaned = [DateTime]::UtcNow.ToString('u')
			}
			$moLock.Put($mo)
		}
		{$_ -in 'tag', 'ref'} {
			if ([Db]::ContainsKey(('pkgdb', $name, $digest))) {
				$dLock, $err = [Db]::TryLock(('pkgdb', $name, $digest))
				if ($err) {
					$locks.Revert()
					throw "package '$digest' is in use by another airpower process"
				}
				$locks += $dLock
				$dLock.Remove()
			}
			if ($m.RefCount -eq 0 -and $m.Orphaned) {
				$m.Remove('Orphaned')
			}
			$m.RefCount += 1
			$mLock.Put($m)
		}
	}
	return $locks, $status
}

function PullPackage {
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[Collections.Hashtable]$Pkg
	)
	$fn, $tag, $digest = $Pkg | ResolveRemotePackage
	WriteHost "Pulling $($Pkg.Package):$($Pkg.Tag | AsTagString) ($tag) $digest"
	$k = 'metadatadb', $digest
	if ([Db]::ContainsKey($k) -and ($m = [Db]::Get($k)) -and $m.Size) {
		$Pkg.Size = $m.Size
	}
	$Pkg.Digest = $digest
	$locks, $status = $Pkg | InstallPackage
	try {
		$ref = "$($Pkg.Package):$($Pkg.Tag | AsTagString)"
		if ($status -eq 'uptodate') {
			WriteHost "Status: Package is up to date for $ref"
		} else {
			if ($status -in 'new', 'newer') {
				$Pkg.Size = & $fn $tag $digest
				if ($Pkg.Size -le 0) {
					throw "failed to retrieve: $ref"
				}
			}
			$refpath = $Pkg | ResolvePackageRefPath
			MakeDirIfNotExist (Split-Path $refpath) | Out-Null
			if (Test-Path -Path $refpath -PathType Container) {
				[IO.Directory]::Delete($refpath)
			}
			New-Item $refpath -ItemType Junction -Target ($Pkg.Digest | ResolvePackagePath) | Out-Null
			"Status: Downloaded newer package for $ref ($($Pkg.Size | AsByteString))" + ' ' * 20 + "`n" | WriteConsole
		}
		$locks.Unlock()
	} finally {
		if ($locks) {
			$locks.Revert()
		}
	}
}

function UninstallPackage { # $locks, $digest, $err
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[Collections.Hashtable]$Pkg
	)
	$name = $Pkg.Package
	$tag = $Pkg.Tag | AsTagString
	$k = 'pkgdb', $name, $tag
	$locks = @()
	if (-not [Db]::ContainsKey($k)) {
		return $null, $null, "package '${name}:$tag' not installed"
	}
	$pLock, $err = [Db]::TryLock($k)
	if ($err) {
		return $null, $null, "package '${name}:$tag' is in use by another airpower process"
	}
	$locks += $pLock
	$p = $pLock.Get()
	$pLock.Remove()
	$mLock, $err = [Db]::TryLock(('metadatadb', $p))
	if ($err) {
		$locks.Revert()
		$null, $null, "package '$p' is in use by another airpower process"
	}
	$locks += $mLock
	$m = $mLock.Get()
	if ($m.refcount -gt 0) {
		$m.refcount -= 1
	}
	if ($m.refcount -eq 0) {
		$mLock.Remove()
		$digest = $p
	} else {
		$mLock.Put($m)
		$digest = $null
	}
	return $locks, $digest, $null
}

function DeleteDirectory {
	param (
		[string]$Dir
	)
	$name = [IO.Path]::GetRandomFileName()
	$tempDir = "$(GetPwrTempPath)\$name"
	[IO.Directory]::CreateDirectory($tempDir) | Out-Null
	try {
		Robocopy.exe $tempDir $Dir /MIR /PURGE | Out-Null
		[IO.Directory]::Delete($Dir)
	} finally {
		[IO.Directory]::Delete($tempDir)
	}
}

function RemovePackage {
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[Collections.Hashtable]$Pkg
	)
	$locks, $digest, $err = $Pkg | UninstallPackage
	if ($null -ne $err) {
		throw $err
	}
	try {
		WriteHost "Untagged: $($Pkg.Package):$($Pkg.Tag | AsTagString)"
		if ($null -ne $digest) {
			$content = $digest | ResolvePackagePath
			if (Test-Path $content -PathType Container) {
				DeleteDirectory $content
			}
			WriteHost "Deleted: $digest"
		}
		$refpath = $Pkg | ResolvePackageRefPath
		if (Test-Path -Path $refpath -PathType Container) {
			[IO.Directory]::Delete($refpath)
		}
		$locks.Unlock()
	} finally {
		if ($locks) {
			$locks.Revert()
		}
	}
}

function UninstallOrphanedPackages {
	param (
		[timespan]$Span
	)
	$now = [datetime]::UtcNow
	$locks = @()
	$metadata = @()
	$ls, $err = [Db]::TryLockAll('metadatadb')
	if ($err) {
		throw $err
	}
	foreach ($lock in $ls) {
		$m = $lock.Get() | ConvertTo-HashTable
		if ($m.orphaned) {
			$orphaned = $now - [datetime]::Parse($m.orphaned)
		}
		if ($m.refcount -eq 0 -and $orphaned -ge $span) {
			$locks += $lock
			$m.digest = $lock.Key[1]
			$metadata += $m
			$lock.Remove()
		} else {
			$lock.Unlock()
		}
	}
	$ls, $err = [Db]::TryLockAll('pkgdb')
	if ($err) {
		if ($locks) {
			$locks.Revert()
		}
		throw $err
	}
	foreach ($lock in $ls) {
		if ($lock.Key[2] -match '^sha256:' -and $lock.Key[2] -in $metadata.digest) {
			$locks += $lock
			$lock.Remove()
		} else {
			$lock.Unlock()
		}
	}
	return $locks, $metadata
}

function PrunePackages {
	param (
		[switch]$Auto
	)
	if ($Auto -and -not (GetAirpowerAutoprune)) {
		return
	}
	$span = if ($Auto) { [timespan]::Parse((GetAirpowerAutoprune)) } else { [timespan]::new(0) }
	$locks, $pruned = UninstallOrphanedPackages $span
	try {
		$bytes = 0
		foreach ($i in $pruned) {
			$content = $i.Digest | ResolvePackagePath
			WriteHost "Deleted: $($i.Digest)"
			$stats = Get-ChildItem $content -Recurse | Measure-Object -Sum Length
			$bytes += $stats.Sum
			if (Test-Path $content -PathType Container) {
				DeleteDirectory $content
			}
		}
		if ($pruned) {
			WriteHost "Total reclaimed space: $($bytes | AsByteString)"
			$locks.Unlock()
		}
	} finally {
		if ($locks) {
			$locks.Revert()
		}
	}
}

class Digest {
	[string]$Sha256

	Digest([string]$sha256) {
		$this.Sha256 = $sha256 | AsDigestString
	}

	[string] ToString() {
		return $this.Sha256
	}
}

function AsDigest {
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
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
	if ($Ref.StartsWith('file:///')) {
		$i = $ref.IndexOf('<')
		$cfg = if ($i -eq -1 -and $ref.Length -gt $i + 1) { 'default' } else { $ref.Substring($i+1).Trim() }
		return @{
			Digest = $Ref
			Tag = 'latest'
			Config = $cfg
		}
	}
	$pkg = $Ref | AsPackage
	$digest = $pkg | ResolvePackageDigest
	switch (GetAirpowerPullPolicy) {
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
			throw "invalid AirpowerPullPolicy '$(GetAirpowerPullPolicy)'"
		}
	}
	return $pkg
}

class Size : IComparable {
	[long]$Bytes
	hidden [string]$ByteString

	Size([long]$Bytes, [string]$ByteString) {
		$this.Bytes = $Bytes
		$this.ByteString = $ByteString
	}

	[int] CompareTo([object]$Obj) {
		return $this.Bytes.CompareTo($Obj.Bytes)
	}

	[string] ToString() {
		return $this.ByteString
	}
}

function AsSize {
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[long]$Bytes
	)
	return [Size]::new($Bytes, ($Bytes | AsByteString))
}

class LocalPackage {
	[object]$Package
	[Tag]$Tag
	[Digest]$Digest
	[Size]$Size
	[object]$Orphaned
	# Signers
}
