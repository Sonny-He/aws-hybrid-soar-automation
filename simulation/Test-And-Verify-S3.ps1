param(
  [string]$Profile = "student",
  [string]$Region = "eu-central-1"
)

$bucketName = "cs1-ma-nca-soar-logs-eu-central-1"

Write-Host "=== S3 Logging Test ===" -ForegroundColor Cyan
Write-Host ""

# Send events
$events = @(
    @{Severity="critical"; EventType="failed_login"; IP="192.168.1.110"; Message="Multiple failed SSH login attempts"},
    @{Severity="critical"; EventType="intrusion_attempt"; IP="10.0.1.50"; Message="Suspected intrusion attempt"},
    @{Severity="high"; EventType="unauthorized_access"; IP="172.16.0.20"; Message="Unauthorized access attempt"},
    @{Severity="medium"; EventType="general_security_event"; IP="192.168.2.100"; Message="Suspicious activity"},
    @{Severity="low"; EventType="informational"; IP="10.0.2.30"; Message="Security scan completed"}
)

foreach ($evt in $events) {
    Write-Host "Sending $($evt.Severity) event: $($evt.EventType)..." -ForegroundColor Yellow
    
    $json = @"
[
  {
    "Source":"soar.test",
    "DetailType":"SecurityEvent",
    "Detail":"{\"severity\":\"$($evt.Severity)\",\"event_type\":\"$($evt.EventType)\",\"source_ip\":\"$($evt.IP)\",\"message\":\"$($evt.Message)\"}",
    "EventBusName":"cs1-ma-nca-soar-events"
  }
]
"@
    
    # Write without BOM
    $enc = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText("temp.json", $json, $enc)
    
    aws events put-events --entries file://temp.json --region $Region --profile $Profile | Out-Null
    Remove-Item temp.json
    
    Write-Host "  Sent!" -ForegroundColor Green
    Start-Sleep -Seconds 2
}

Write-Host ""
Write-Host "Waiting 30 seconds for processing..." -ForegroundColor Yellow
Start-Sleep -Seconds 30

# Verify S3
$year = (Get-Date).Year
$month = (Get-Date).ToString("MM")
$day = (Get-Date).ToString("dd")

Write-Host ""
Write-Host "=== S3 Files ===" -ForegroundColor Cyan
aws s3 ls "s3://$bucketName/events/$year/$month/$day/" --recursive --region $Region --profile $Profile

Write-Host ""
Write-Host "=== Checking Encryption ===" -ForegroundColor Cyan
$fileKey = aws s3api list-objects-v2 --bucket $bucketName --prefix "events/$year/$month/$day/" --max-items 1 --region $Region --profile $Profile --query "Contents[0].Key" --output text

if ($fileKey -and $fileKey -ne "None") {
    $encryption = aws s3api head-object --bucket $bucketName --key $fileKey --region $Region --profile $Profile --query "ServerSideEncryption" --output text
    Write-Host "Encryption: $encryption" -ForegroundColor Green
} else {
    Write-Host "No files found to check encryption" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Done! Now take screenshots from S3 console:" -ForegroundColor Green
Write-Host "https://s3.console.aws.amazon.com/s3/buckets/$bucketName" -ForegroundColor Cyan