param(
  [string]$Cluster = "cs1-ma-nca-soar-cluster",
  [string]$Service = "cs1-ma-nca-soar-service",
  [string]$Profile = "student",
  [string]$Region  = "eu-central-1",
  [int]$Port = 5140,
  [string]$Message = "Failed login attempt from 192.168.1.110",
  [int]$Priority = 34,
  [switch]$AllTasks
)

Write-Host "=== Syslog SOAR Test ==="
Write-Host ""

# Get task IPs
$taskArns = aws ecs list-tasks --cluster $Cluster --service-name $Service --region $Region --profile $Profile --query "taskArns[]" --output text

$ips = @()
foreach ($arn in $taskArns -split '\s+') {
  if ($arn) {
    $ip = aws ecs describe-tasks --cluster $Cluster --tasks $arn --region $Region --profile $Profile --query "tasks[0].attachments[0].details[?name=='privateIPv4Address'].value" --output text
    if ($ip -and $ip -ne "None") { 
      $ips += $ip 
      Write-Host "Found task: $ip"
    }
  }
}

if ($ips.Count -eq 0) {
  Write-Host "No tasks found!"
  exit 1
}

# Send to first task only (or all if -AllTasks flag)
if ($AllTasks) {
  $targetIps = $ips
} else {
  $targetIps = @($ips[0])
  Write-Host "Sending to first task only"
}

Write-Host ""

# Send syslog
$ts = (Get-Date).ToString("MMM dd HH:mm:ss")
$payload = "<$Priority>$ts $env:COMPUTERNAME SOARTest: $Message"
$bytes = [Text.Encoding]::ASCII.GetBytes($payload)

foreach ($ip in $targetIps) {
  $u = [System.Net.Sockets.UdpClient]::new()
  [void]$u.Send($bytes, $bytes.Length, $ip, $Port)
  $u.Close()
  Write-Host "Sent to $ip"
  Write-Host "Payload: $payload"
}

Write-Host ""
Write-Host "Expected: $($targetIps.Count * 2) emails"