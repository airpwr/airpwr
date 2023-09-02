. $PSScriptRoot\..\github.ps1

function AirpowerPackageNats-Server {
	param (
		[string]$TagName,
		[string]$Digest
	)
	return AirpowerGitHubPackage -Owner 'nats-io' -Repo 'nats-server' -Digest $Digest -TagName $TagName -TagPattern '^v([0-9]+)\.([0-9]+)\.([0-9]+)$' -UrlFormat 'https://github.com/nats-io/nats-server/releases/download/v{0}/nats-server-v{0}-windows-amd64.zip' -IncludeFiles 'nats-server.exe'
}
