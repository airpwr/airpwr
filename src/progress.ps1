# U+2588	█	Full block
# U+258C	▌	Left half block

function GetUnicodeBlock {
	param (
		[Parameter(Mandatory)]
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
	$p = $Current / $Total
	$inc = 1 / $width
	$full = [int][Math]::Floor($p / $inc)
	$left = [int][Math]::Floor((($p - ($inc * $full)) / $inc) * 2)
	$line = "$esc[94m$esc[47m" + ((GetUnicodeBlock 2) * $full)
	if ($full -lt $width) {
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
	if (($null -eq $lastwrite) -or (((Get-Date) - $lastwrite).TotalMilliseconds -gt 125)) {
		$line = & $DeferLine
		WriteConsole $line
		$script:lastwrite = (Get-Date)
	}
}

function SetCursorVisible {
	param (
		[Parameter(Mandatory)]
		[bool]$Enable
	)
	try {
		[Console]::CursorVisible = $Enable
	} catch {
		Write-Error $_ -ErrorAction Ignore
	}
}

function WriteConsole {
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[string]$Line
	)
	if ($ProgressPreference -eq 'Continue') {
		[Console]::Write("`r$Line")
	} elseif ($ProgressPreference -ne 'SilentlyContinue') {
		throw "cannot write progress for ProgressPreference=$ProgressPreference"
	}
}

function AsByteString {
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[long]$Bytes,
		[switch]$FixDecimals
	)
	$n = [Math]::Abs($Bytes)
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
	return "{0:0.$(if ($FixDecimals) { '00' } else { '##' })} {1}B" -f $n, $r[[Math]::Min(9, $p)]
}
