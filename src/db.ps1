. $PSScriptRoot\config.ps1

class FileLock {
	hidden [IO.FileStream]$File

	FileLock([string]$Path, [IO.FileAccess]$Access) {
		$this.File = [IO.FileStream]::new($Path, [IO.FileMode]::OpenOrCreate, $Access, [IO.FileShare]::Read)
	}

	static [FileLock] RLock([string]$Path) {
		return [FileLock]::new($Path, [IO.FileAccess]::Read)
	}

	static [FileLock] Lock([string]$Path) {
		return [FileLock]::new($Path, [IO.FileAccess]::ReadWrite)
	}

	Unlock() {
		$this.File.Dispose()
	}

	[object] Get() {
		$b = [byte[]]::new($this.File.Length)
		$this.File.Read($b, 0, $this.File.Length)
		return [Db]::Decode([Text.Encoding]::UTF8.GetString($b))
	}

	Put([object]$Value) {
		$this.File.SetLength(0)
		$content = [Db]::Encode($value)
		$this.File.Write([Text.Encoding]::UTF8.GetBytes($content), 0, [Text.Encoding]::UTF8.GetByteCount($content))
	}
}

class Db {
	static hidden [string]$Dir

	static Db() {
		try {
		[Db]::Dir = "$(GetAirpowerPath)\cache"
		MakeDirIfNotExist ([Db]::Dir)
		} catch {
			Write-Host $_
		}
	}

	static [object] Get([string[]]$key) {
		return [Db]::Decode([IO.File]::ReadAllText("$([Db]::Dir)\$([Db]::Key($key))"))
	}

	static [Result] TryGet([string[]]$key) {
		try {
			return @{
				Value = [Db]::Get([string[]]$key)
			}
		} catch {
			return @{
				Err = $_
			}
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
		return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($value | ConvertTo-Json -Compress -Depth 10)))
	}

	static [object] Decode([string]$value) {
		return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($value)) | ConvertFrom-Json
	}

	static [FileLock] Lock([string[]]$key) {
		return [FileLock]::Lock("$([Db]::Dir)\$([Db]::Key($key))")
	}

	static [FileLock] RLock([string[]]$key) {
		return [FileLock]::RLock("$([Db]::Dir)\$([Db]::Key($key))")
	}

	static [string] Key([string[]]$key) {
		$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($key -join '.'))
		return $b64.Replace('/', '_').Replace('+', '-')
	}

	static [string[]] DecodeKey([string]$b64) {
		return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64.Replace('_', '/').Replace('-', '+'))) -split '\.'
	}

	static [bool] HasPrefix([string]$b64, [string[]]$key) {
		$s = [Db]::DecodeKey($b64)
		return $s.StartsWith($key -join '.')
	}

	static [Entry[]] GetAll([string[]]$key) {
		$entries = @()
		foreach ($f in [IO.Directory]::GetFiles([Db]::Dir)) {
			$k = $f.Substring([Db]::Dir.Length+1)
			if ([Db]::HasPrefix($k, $key)) {
				$decodedKey = [Db]::DecodeKey($k)
				$res = [Db]::TryGet($decodedKey)
				if (-not $res.Err) {
					$entries += @{
						Key = $decodedKey
						Value = $res.Value
					}
				}
			}
		}
		return $entries
	}
}

class Entry {
	[string[]]$Key
	[object]$Value
}

class Result {
	[object]$Value
	[Management.Automation.ErrorRecord]$Err
}
