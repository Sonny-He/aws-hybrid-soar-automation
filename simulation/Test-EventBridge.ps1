param(
  [string]$Profile = "student",
  [string]$Region  = "eu-central-1",
  [string]$Severity = "high",
  [string]$EventType = "test_event",
  [string]$Message = "Test event from EventBridge",
  [string]$SourceIP = "192.168.1.100"  # NEW PARAMETER
)

Write-Host "=== EventBridge SOAR Test ==="
Write-Host ""

# Create event file
$eventFile = "event-temp.json"
$json = @"
[
  {
    "Source":"soar.test",
    "DetailType":"SecurityEvent",
    "Detail":"{\"severity\":\"$Severity\",\"event_type\":\"$EventType\",\"source_ip\":\"$SourceIP\",\"message\":\"$Message\"}",
    "EventBusName":"cs1-ma-nca-soar-events"
  }
]
"@

$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($eventFile, $json, $enc)

# Send event
Write-Host "Sending event with IP: $SourceIP"
aws events put-events --entries "file://$eventFile" --region $Region --profile $Profile

# Cleanup
Remove-Item $eventFile

Write-Host ""
Write-Host "Expected: 2 emails"