param(
  [string]$Cluster = "cs1-ma-nca-soar-cluster",
  [string]$Service = "cs1-ma-nca-soar-service",
  [string]$Profile = "student",
  [string]$Region  = "eu-central-1",
  [int]$Port = 5140,
  [string]$Message = "Failed login attempt from 192.168.1.110"
)

# --- discover task IPs ---
$taskArns = (aws ecs list-tasks --cluster $Cluster --service-name $Service `
  --region $Region --profile $Profile --query "taskArns[]" --output text)

$ips = @()
if ($taskArns) {
  foreach ($arn in $taskArns -split '\s+') {
    if (-not [string]::IsNullOrWhiteSpace($arn)) {
      $ip = aws ecs describe-tasks --cluster $Cluster --tasks $arn `
        --region $Region --profile $Profile `
        --query "tasks[0].attachments[0].details[?name=='privateIPv4Address'].value" --output text
      if ($ip -and $ip -ne "None") { $ips += $ip }
    }
  }
}

if (-not $ips) {
  Write-Host "No task IPs found for $Service in $Cluster." -ForegroundColor Yellow
} else {
  # --- send UDP syslog to each task ---
  $ts = (Get-Date).ToString("MMM dd HH:mm:ss")
  $payload = "<34>$ts $env:COMPUTERNAME SOARTest: $Message"
  $bytes = [Text.Encoding]::ASCII.GetBytes($payload)

  foreach ($ip in $ips) {
    $u = [System.Net.Sockets.UdpClient]::new()
    [void]$u.Send($bytes,$bytes.Length,$ip,$Port); $u.Close()
    Write-Host ("Sent to {0}:{1} -> {2}" -f $ip, $Port, $payload)
  }
}

# --- EventBridge test event (no BOM) ---
$eventFile = Join-Path $PWD "event.json"
$json = @"
[
  {
    "Source":"soar.test",
    "DetailType":"SecurityEvent",
    "Detail":"{\"severity\":\"high\",\"message\":\"Test event\"}",
    "EventBusName":"cs1-ma-nca-soar-events"
  }
]
"@

$enc = New-Object System.Text.UTF8Encoding($false)  # no BOM
[IO.File]::WriteAllText($eventFile, $json, $enc)

aws events put-events --entries ("file://{0}" -f $eventFile) `
  --region $Region --profile $Profile
