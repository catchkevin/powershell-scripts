# Function to display the note on syntax
function Show-SyntaxNote {
    Write-Host "Note: To manually add ports, use a comma-separated list without spaces."
    Write-Host "Example for a single port: 80"
    Write-Host "Example for multiple ports: 80, 443, 8080"
    Write-Host
}

# Predefined list of ports
$defaultPorts = @(53, 88, 123, 135, 139, 389, 445, 464, 593, 636, 3268, 3269, 49152, 65535)

# Prompt user for input
Write-Host "Please Select One:"
Write-Host "Press 1: Use default ports"
Write-Host "Press 2: Input a custom list of ports:"
$selection = Read-Host

# Validate and get the list of ports
switch ($selection) {
    1 {
        $ports = $defaultPorts
    }
    2 {
        Show-SyntaxNote
        Write-Host "Enter your list of ports (comma-separated):"
        $customPorts = Read-Host
        $ports = $customPorts -split ',' | ForEach-Object { [int]$_ }
    }
    default {
        Write-Host "Invalid selection. Using default ports."
        $ports = $defaultPorts
    }
}

$ips = @("127.0.0.1", "0.0.0.0")
$results = @()

foreach ($ip in $ips) {
    foreach ($port in $ports) {
        $tcpListener = New-Object Net.Sockets.TcpListener($ip, $port)
        try {
            $tcpListener.Start()
            $tcpListener.Stop()
            $status = "Closed"
            $color = "Red"
        } catch {
            $status = "Open"
            $color = "Green"
        }
        
        $results += [PSCustomObject]@{
            IP     = $ip
            Port   = $port
            Status = $status
        }
    }
}

# Display the table headers
$headers = "IP", "Port", "Status"
$formatString = "{0,-15} {1,-6} {2,-7}"

# Output headers
$headerRow = $formatString -f $headers[0], $headers[1], $headers[2]
Write-Host $headerRow -ForegroundColor Cyan

# Output rows with color
$results | ForEach-Object {
    $statusColor = if ($_.Status -eq "Open") { "Green" } else { "Red" }
    $formattedOutput = $formatString -f $_.IP, $_.Port, $_.Status
    Write-Host $formattedOutput -ForegroundColor $statusColor
}
