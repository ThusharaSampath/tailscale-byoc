# JQ Query Templates for Tailscale Network Flow Logs

## Basic Template: Flows from IP X to IP Y

Replace `SRC_IP` and `DST_IP` with your IPs (e.g., "100.97.54.81", "172.16.20.88")

### 1. Search Subnet Traffic (clients → subnets)

```bash
SRC_IP="100.85.22.116"
DST_IP="172.16.4.207"

jq --arg src "$SRC_IP" --arg dst "$DST_IP" '
  .logs[] | .subnetTraffic[]? 
  | select(.src | contains($src)) 
  | select(.dst | contains($dst))
' LOGS/tailscale_network_flow_logfile.txt | head -10
```

### 2. Search Physical Traffic (node → node, node → DERP)

```bash
SRC_IP="100.97.54.81"
DST_IP="65.51.181.220"

jq --arg src "$SRC_IP" --arg dst "$DST_IP" '
  .logs[] | .physicalTraffic[]? 
  | select(.src | contains($src)) 
  | select(.dst | contains($dst))
' LOGS/tailscale_network_flow_logfile.txt | head -10
```

### 3. Count flows with timestamp

```bash
SRC_IP="100.85.22.116"
DST_IP="172.16.20.88"

jq --arg src "$SRC_IP" --arg dst "$DST_IP" '
  .logs[] 
  | select(.logged != null) as $log
  | .subnetTraffic[]? 
  | select(.src | contains($src)) 
  | select(.dst | contains($dst))
  | {
      time: $log.logged,
      src: .src,
      dst: .dst,
      txPkts: .txPkts,
      txBytes: .txBytes,
      status: (if .txPkts == 1 then "FAILED" else "SUCCESS" end)
    }
' LOGS/tailscale_network_flow_logfile.txt
```

### 4. Get count of flows

```bash
SRC_IP="100.108.154.52"
DST_IP="172.16.20.88"

jq --arg src "$SRC_IP" --arg dst "$DST_IP" '
  [.logs[] | .subnetTraffic[]? 
   | select(.src | contains($src)) 
   | select(.dst | contains($dst))] 
  | length
' LOGS/tailscale_network_flow_logfile.txt
```

### 5. Get aggregated statistics

```bash
SRC_IP="100.85.22.116"
DST_IP="172.16.4.207"

jq --arg src "$SRC_IP" --arg dst "$DST_IP" '
  [.logs[] | .subnetTraffic[]? 
   | select(.src | contains($src)) 
   | select(.dst | contains($dst))]
  | {
      total_flows: length,
      failed_flows: ([.[] | select(.txPkts == 1)] | length),
      total_bytes: ([.[] | .txBytes] | add),
      total_packets: ([.[] | .txPkts] | add)
    }
  | . + {
      failure_rate: ((.failed_flows / .total_flows * 100) | tostring + "%")
    }
' LOGS/tailscale_network_flow_logfile.txt
```

### 6. Filter by time period

```bash
SRC_IP="100.97.54.81"
DST_IP="65.51.181.220"
START_TIME="2025-10-21T05:50:00Z"
END_TIME="2025-10-21T06:30:00Z"

jq --arg src "$SRC_IP" --arg dst "$DST_IP" \
   --arg start "$START_TIME" --arg end "$END_TIME" '
  .logs[] 
  | select(.logged >= $start and .logged <= $end)
  | .physicalTraffic[]? 
  | select(.src | contains($src)) 
  | select(.dst | contains($dst))
' LOGS/tailscale_network_flow_logfile.txt
```

### 7. Find all destinations from a source IP

```bash
SRC_IP="100.85.22.116"

jq --arg src "$SRC_IP" '
  [.logs[] | .subnetTraffic[]? 
   | select(.src | contains($src)) 
   | .dst] 
  | group_by(.) 
  | map({dst: .[0], count: length}) 
  | sort_by(.count) 
  | reverse
' LOGS/tailscale_network_flow_logfile.txt
```

### 8. Find all sources to a destination IP

```bash
DST_IP="172.16.20.88"

jq --arg dst "$DST_IP" '
  [.logs[] | .subnetTraffic[]? 
   | select(.dst | contains($dst)) 
   | .src] 
  | group_by(.) 
  | map({src: .[0], count: length}) 
  | sort_by(.count) 
  | reverse
' LOGS/tailscale_network_flow_logfile.txt
```

## Common Use Cases

### Check Windows VM → DERP traffic during outage

```bash
jq '.logs[] 
  | select(.logged >= "2025-10-21T05:50:00Z" and .logged <= "2025-10-21T06:30:00Z")
  | .physicalTraffic[]? 
  | select(.src | contains("100.97.54.81")) 
  | select(.dst | contains("65.51.181.220"))
  | {time: .logged, txPkts, rxPkts, txBytes, rxBytes}
' LOGS/tailscale_network_flow_logfile.txt | head -20
```

### Check specific client → database failures

```bash
jq '.logs[] | .subnetTraffic[]? 
  | select(.src | contains("100.85.22.116")) 
  | select(.dst | contains("172.16.4.207"))
  | select(.txPkts == 1)  # Only failed flows
' LOGS/tailscale_network_flow_logfile.txt | head -10
```

### Check successful connections from a client

```bash
jq '.logs[] | .subnetTraffic[]? 
  | select(.src | contains("100.91.59.61")) 
  | select(.dst | contains("172.16.20.88"))
  | select(.txPkts > 1)  # Only successful flows
' LOGS/tailscale_network_flow_logfile.txt | head -10
```

## Quick Copy-Paste Templates

### Template 1: Simple flow listing
```bash
jq --arg src "SOURCE_IP" --arg dst "DEST_IP" '
  .logs[] | .subnetTraffic[]? 
  | select(.src | contains($src)) 
  | select(.dst | contains($dst))
' LOGS/tailscale_network_flow_logfile.txt
```

### Template 2: Count only
```bash
jq --arg src "SOURCE_IP" --arg dst "DEST_IP" '
  [.logs[] | .subnetTraffic[]? 
   | select(.src | contains($src)) 
   | select(.dst | contains($dst))] | length
' LOGS/tailscale_network_flow_logfile.txt
```

### Template 3: With statistics
```bash
jq --arg src "SOURCE_IP" --arg dst "DEST_IP" '
  [.logs[] | .subnetTraffic[]? 
   | select(.src | contains($src)) 
   | select(.dst | contains($dst))]
  | {
      total: length,
      failed: ([.[] | select(.txPkts == 1)] | length),
      success: ([.[] | select(.txPkts > 1)] | length)
    }
' LOGS/tailscale_network_flow_logfile.txt
```

## IP Address Patterns in Logs

- **Tailscale IPs**: `100.x.x.x` (all nodes in Tailscale network)
- **Private subnets**: `172.16.x.x` (customer private network)
- **DERP relay**: `65.51.181.220:41641` (Tailscale's relay server)
- **Internal DERP**: `127.3.3.40:1` or `127.3.3.40:27` (localhost DERP)

## Field Reference

**subnetTraffic fields:**
- `proto`: Protocol (6 = TCP, 1 = ICMP)
- `src`: Source IP:port
- `dst`: Destination IP:port
- `txPkts`: Packets sent
- `txBytes`: Bytes sent

**physicalTraffic fields:**
- `src`: Source IP:port
- `dst`: Destination IP:port
- `txPkts`: Packets sent
- `txBytes`: Bytes sent
- `rxPkts`: Packets received
- `rxBytes`: Bytes received
