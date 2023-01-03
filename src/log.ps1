function WriteHost {
	param (
		[string]$Line
	)
	Write-Information $Line -InformationAction Continue
}
