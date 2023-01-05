# U+2588	█	Full block
# U+2589	▉	Left seven eighths block
# U+258A	▊	Left three quarters block
# U+258B	▋	Left five eighths block
# U+258C	▌	Left half block
# U+258D	▍	Left three eighths block
# U+258E	▎	Left one quarter block
# U+258F	▏	Left one eighth block

function GetUnicodeBlock {
	param (
		[Parameter(Mandatory = $true)]
		[int]$Index
	)
	@{
		0 = " "
		1 = "$([char]0x258c)"
		2 = "$([char]0x2588)"
	}[$Index]
}

function GetProgress {
	param (
		[Parameter(Mandatory)]
		[long]$Current,
		[Parameter(Mandatory)]
		[long]$Total
	)
	$width = 30
	$esc = [char]27
	$p = $Current/$Total
	$inc = 1/$width
	$full = [int][Math]::Floor($p / $inc)
	$left = [int][Math]::Floor((($p - ($inc * $full)) / $inc) * 2)
	$line = "$esc[94m$esc[47m" + ((GetUnicodeBlock 2) * $full)
	if ($full -ne $width) {
		$line += (GetUnicodeBlock $left) + (" " * ($width - $full - 1))
	}
	$stat = '{0,10} / {1,-10}' -f ($Current | AsByteString -FixDecimals), ($Total | AsByteString)
	$line += "$esc[0m $stat"
	return "$line$esc[0m"
}

function WritePeriodicConsole {
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[scriptblock]$DeferLine
	)
	if (($null -eq $lastwrite) -or (((get-date) - $lastwrite).TotalMilliseconds -gt 125)) {
		$line = & $DeferLine
		[Console]::Write("`r$line")
		$script:lastwrite = (get-date)
	}
}

function WriteConsole {
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[string]$Line
	)
	[Console]::Write("`r$Line")
}

function AsByteString {
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[long]$Bytes,
		[switch]$FixDecimals
	)
	$n = [math]::Abs($Bytes)
	$p = 0
	while ($n -gt 1024) {
		$n /= 1024
		$p += 3
	}
	$r = @{
		0 = ''
		3 = 'k'
		6 = 'M'
		9 = 'G'
	}
	return "{0:0.$(if ($FixDecimals) { '00' } else { '##' })} {1}B" -f $n, $r[[math]::min(9, $p)]
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
		[Parameter(
			Mandatory = $true,
			ValueFromPipeline = $true)]
		[long]$Bytes
	)
	return [Size]::new($Bytes, ($Bytes | AsByteString))
}
