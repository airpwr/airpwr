param (
	[string]$Name
)
$z = @{
	Name = $Name
}

airpower exec 'go' {
	Write-Host "Hello $($z.Name)!"
}
