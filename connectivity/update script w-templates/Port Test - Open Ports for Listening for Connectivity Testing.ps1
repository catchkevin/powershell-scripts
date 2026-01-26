# Specify the list of ports you want to listen on
$ports = @(53, 88, 123, 135, 139, 389, 445, 464, 593, 636, 3268, 3269, 49152, 65535)

# Create lists to hold the listeners and skipped ports
$listeners = @()
$skippedPorts = @()

# Function to check if a port is already in use
function Test-PortAvailability {
    param ([int]$port)
    $tcpListener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, $port)
    try {
        $tcpListener.Start()
        $tcpListener.Stop()
        return $true
    } catch {
        return $false
    }
}

# Start a listener on each available port
foreach ($port in $ports) {
    if (Test-PortAvailability -port $port) {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $port)
        $listener.Start()
        $listeners += $listener
        Write-Host "Listening on port $port..."
    } else {
        $skippedPorts += $port
        Write-Host "Port $port is already in use and was not opened."
    }
}

if ($skippedPorts.Count -gt 0) {
    Write-Host "The following ports were skipped because they are already in use: $($skippedPorts -join ', ')"
}

Write-Host "Press Ctrl+C to stop all listeners."

try {
    while ($true) {
        foreach ($listener in $listeners) {
            if ($listener.Pending()) {
                $client = $listener.AcceptTcpClient()
                Write-Host "Received a connection on port $($listener.LocalEndpoint.Port) from $($client.Client.RemoteEndPoint)"
                $client.Close()
            }
        }

        # Small delay to prevent high CPU usage
        Start-Sleep -Milliseconds 500
    }
}
catch {
    Write-Host "Stopping all listeners..."
}
finally {
    # Ensure all listeners are stopped when the script exits
    foreach ($listener in $listeners) {
        $listener.Stop()
    }
    Write-Host "All listeners have been stopped."
}
