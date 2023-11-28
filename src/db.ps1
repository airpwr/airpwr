. $PSScriptRoot\config.ps1

class FileLock {
	hidden [IO.FileStream]$File
	hidden [IO.MemoryStream]$Buffer
	hidden [string]$Path
	hidden [IO.FileAccess]$Access
	hidden [bool]$Delete
	[string[]]$Key

	FileLock([string]$Path, [IO.FileAccess]$Access, [string[]]$Key) {
		$this.Key = $Key
		$this.Access = $Access
		$this.Path = $Path
		$this.File = [IO.FileStream]::new($Path, [IO.FileMode]::OpenOrCreate, $Access, [IO.FileShare]::Read)
		if ($Access -eq [IO.FileAccess]::ReadWrite) {
			$this.Buffer = [IO.MemoryStream]::new()
		}
	}

	static [FileLock] RLock([string]$Path, [string[]]$Key) {
		return [FileLock]::new($Path, [IO.FileAccess]::Read, $Key)
	}

	static [FileLock] Lock([string]$Path, [string[]]$Key) {
		return [FileLock]::new($Path, [IO.FileAccess]::ReadWrite, $Key)
	}

	Unlock() {
		if ($this.Buffer) {
			if ($this.Buffer.Length -gt 0) {
				$this.File.SetLength(0)
				$this.Buffer.WriteTo($this.File)
			}
		}
		$this.File.Dispose()
		if ($this.Delete) {
			[IO.File]::Delete($this.Path)
		}
	}

	Revert() {
		$this.File.Dispose()
	}

	Remove() {
		$this.Delete = $this.Access -eq [IO.FileAccess]::ReadWrite
	}

	[object] Get() {
		$b = [byte[]]::new($this.File.Length)
		$this.File.Read($b, 0, $this.File.Length)
		return [Db]::Decode([Text.Encoding]::UTF8.GetString($b))
	}

	Put([object]$Value) {
		$content = [Db]::Encode($value)
		$this.Buffer.Write([Text.Encoding]::UTF8.GetBytes($content), 0, [Text.Encoding]::UTF8.GetByteCount($content))
	}
}

class Db {
	static [string]$Dir = (GetPwrDbPath)

	static Db() {
		[Db]::Init()
	}

	static Init() {
		MakeDirIfNotExist ([Db]::Dir)
	}

	static Remove([string[]]$key) {
		[IO.File]::Delete("$([Db]::Dir)\$([Db]::Key($key))")
	}

	static [object] Get([string[]]$key) {
 		return [Db]::Decode([IO.File]::ReadAllText("$([Db]::Dir)\$([Db]::Key($key))"))
	}

	static [object[]] TryGet([string[]]$key) {
		try {
			return [Db]::Get($key), $null
		} catch {
			return $null, $_
		}
	}

	static Put([string[]]$key, [object]$value) {
		[IO.File]::WriteAllText("$([Db]::Dir)\$([Db]::Key($key))", [Db]::Encode($value))
	}

	static [bool] TryPut([string[]]$key, [object]$value) {
		try {
			[Db]::TryPut($key, $value)
			return $true
		} catch {
			return $false
		}
	}

	static [string] Encode([object]$value) {
		$json = $value | ConvertTo-Json -Compress -Depth 10
		if ($null -eq $json) {
			$json = 'null' # PS 5.1 does not handle null
		}
		return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
	}

	static [object] Decode([string]$value) {
		return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($value)) | ConvertFrom-Json
	}

	static [FileLock] Lock([string[]]$key) {
		return [FileLock]::Lock("$([Db]::Dir)\$([Db]::Key($key))", $key)
	}

	static [object[]] TryLock([string[]]$key) {
		try {
			return [Db]::Lock($key), $null
		} catch {
			return $null, $_
		}
	}

	static [FileLock] RLock([string[]]$key) {
		return [FileLock]::RLock("$([Db]::Dir)\$([Db]::Key($key))", $key)
	}

	static [object[]] TryRLock([string[]]$key) {
		try {
			return [Db]::RLock($key), $null
		} catch {
			return $null, $_
		}
	}

	static [string] Key([string[]]$key) {
		$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($key -join "`n"))
		return $b64.Replace('/', '_').Replace('+', '-')
	}

	static [string[]] DecodeKey([string]$b64) {
		return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64.Replace('_', '/').Replace('-', '+'))) -split "`n"
	}

	static [bool] HasPrefix([string]$b64, [string[]]$key) {
		$s = [Db]::DecodeKey($b64)
		for($i=0; $i -lt $key.Length; $i+=1) {
			if ($key[$i] -ne $s[$i]) {
				return $false
			}
		}
		return $true
	}

	static [bool] ContainsKey([string[]]$key) {
		return [IO.File]::Exists("$([Db]::Dir)\$([Db]::Key($key))")
	}

	static [Entry[]] GetAll([string[]]$key) {
		$entries = @()
		foreach ($f in [IO.Directory]::GetFiles([Db]::Dir)) {
			$k = $f.Substring([Db]::Dir.Length+1)
			if ([Db]::HasPrefix($k, $key)) {
				$decodedKey = [Db]::DecodeKey($k)
				$v, $err = [Db]::TryGet($decodedKey)
				if (-not $err) {
					$entries += @{
						Key = $decodedKey
						Value = $v
					}
				}
			}
		}
		return $entries
	}

	static [object[]] TryLockAll([string[]]$key) {
		$locks = @()
		foreach ($f in [IO.Directory]::GetFiles([Db]::Dir)) {
			$k = $f.Substring([Db]::Dir.Length+1)
			if ([Db]::HasPrefix($k, $key)) {
				$decodedKey = [Db]::DecodeKey($k)
				try {
					$locks += [Db]::Lock($decodedKey)
				} catch {
					if ($locks) {
						$locks.Revert()
					}
					return $null, "a package $decodedKey is being used by another airpower process"
				}
			}
		}
		return $locks, $null
	}
}

class Entry {
	[string[]]$Key
	[object]$Value
}
