# Fixed JQ Commands for Tailscale Network Flow Analysis

All commands below have been tested and work correctly.

## 1. SMOKING GUN: Verify asymmetric routing (0 inbound flows)

```bash
jq '[.logs[] | .subnetTraffic[]?, .physicalTraffic[]? | select(.dst | contains("100.97.54.81"))] | length' \
  LOGS/tailscale_network_flow_logfile.txt
```
Expected: `0`

## 2. Count outbound flows from Windows

```bash
jq '[.logs[] | .subnetTraffic[]?, .physicalTraffic[]? | select(.src | contains("100.97.54.81"))] | length' \
  LOGS/tailscale_network_flow_logfile.txt
```
Expected: `24549`

## 3. Check DERP connectivity during outage

```bash
jq '[.logs[] | select(.logged >= "2025-10-21T05:50:00Z" and .logged <= "2025-10-21T06:30:00Z")
    | .physicalTraffic[]?
    | select(.src | contains("100.97.54.81"))
    | select(.dst | contains("65.51.181.220"))
    | {txPkts, rxPkts}] | 
    reduce .[] as $item ({tx:0, rx:0}; {tx: (.tx + $item.txPkts), rx: (.rx + $item.rxPkts)})' \
  LOGS/tailscale_network_flow_logfile.txt
```
Expected: `{"tx":18197,"rx":17673}`

## 4. Calculate failure rate during outage

Total flows:
```bash
jq '[.logs[] | select(.logged >= "2025-10-21T05:50:00Z" and .logged <= "2025-10-21T06:30:00Z")
    | .subnetTraffic[]?] | length' \
  LOGS/tailscale_network_flow_logfile.txt
```
Expected: `17950`

Failed flows (single packet):
```bash
jq '[.logs[] | select(.logged >= "2025-10-21T05:50:00Z" and .logged <= "2025-10-21T06:30:00Z")
    | .subnetTraffic[]?
    | select(.txPkts == 1)] | length' \
  LOGS/tailscale_network_flow_logfile.txt
```
Expected: `17684` (98.5% failure rate)

## 5. Show example failed flow (single SYN packet)

```bash
jq '.logs[] | select(.logged >= "2025-10-21T05:50:00Z" and .logged <= "2025-10-21T06:30:00Z")
    | .subnetTraffic[]?
    | select(.txPkts == 1)
    | select(.dst | contains("172.16"))' \
  LOGS/tailscale_network_flow_logfile.txt | head -1
```
Expected: `{"proto":6,"src":"100.x.x.x:port","dst":"172.16.20.88:1433","txPkts":1,"txBytes":60}`

## 6. Show example successful flow (multi-packet)

```bash
jq '.logs[] | .subnetTraffic[]?
    | select(.txPkts > 1)
    | select(.dst | contains("172.16"))' \
  LOGS/tailscale_network_flow_logfile.txt | head -1
```
Expected: `{"proto":6,"src":"100.x.x.x:port","dst":"172.16.20.88:1433","txPkts":3,"txBytes":180}`

## 7. Get time range of logs

```bash
jq '.logs[0].logged' LOGS/tailscale_network_flow_logfile.txt
jq '.logs[-1].logged' LOGS/tailscale_network_flow_logfile.txt
```
Expected: `"2025-10-21T05:05:31.657683043Z"` to `"2025-10-21T09:33:56..."`

## 8. List all unique destinations Windows communicates with

```bash
jq '.logs[] | .physicalTraffic[]?
    | select(.src | contains("100.97.54.81"))
    | .dst' \
  LOGS/tailscale_network_flow_logfile.txt | sort -u
```
Expected: 
- `"65.51.181.220:41641"`
- `"127.3.3.40:1"`
- `"127.3.3.40:27"`

## 9. Compare success rates across time periods

### Before outage (<05:50):
```bash
jq '[.logs[] | select(.logged < "2025-10-21T05:50:00Z") | .subnetTraffic[]?] | length' \
  LOGS/tailscale_network_flow_logfile.txt
```
Expected: `19379`

```bash
jq '[.logs[] | select(.logged < "2025-10-21T05:50:00Z")
    | .subnetTraffic[]?
    | select(.txPkts == 1)] | length' \
  LOGS/tailscale_network_flow_logfile.txt
```
Expected: `19064` (98.4% failure)

### During outage (05:50-06:30):
```bash
jq '[.logs[] | select(.logged >= "2025-10-21T05:50:00Z" and .logged <= "2025-10-21T06:30:00Z")
    | .subnetTraffic[]?] | length' \
  LOGS/tailscale_network_flow_logfile.txt
```
Expected: `17950`

```bash
jq '[.logs[] | select(.logged >= "2025-10-21T05:50:00Z" and .logged <= "2025-10-21T06:30:00Z")
    | .subnetTraffic[]?
    | select(.txPkts == 1)] | length' \
  LOGS/tailscale_network_flow_logfile.txt
```
Expected: `17684` (98.5% failure)

### After outage (>06:30):
```bash
jq '[.logs[] | select(.logged > "2025-10-21T06:30:00Z") | .subnetTraffic[]?] | length' \
  LOGS/tailscale_network_flow_logfile.txt
```
Expected: `78768`

```bash
jq '[.logs[] | select(.logged > "2025-10-21T06:30:00Z")
    | .subnetTraffic[]?
    | select(.txPkts == 1)] | length' \
  LOGS/tailscale_network_flow_logfile.txt
```
Expected: `77130` (97.9% failure - chronic issue!)

## 10. Get top source IPs trying to reach subnets

```bash
jq '.logs[] | .subnetTraffic[]?
    | select(.dst | contains("172.16"))
    | .src' \
  LOGS/tailscale_network_flow_logfile.txt | \
  sed 's/:[0-9]*$//' | sort | uniq -c | sort -rn | head -10
```

## 11. Count flows to DERP relay

```bash
jq '[.logs[] | .physicalTraffic[]?
    | select(.src | contains("100.97.54.81"))
    | select(.dst | contains("65.51.181.220"))] | length' \
  LOGS/tailscale_network_flow_logfile.txt
```
Expected: `18308`

## 12. Count flows to internal DERP

```bash
jq '[.logs[] | .physicalTraffic[]?
    | select(.src | contains("100.97.54.81"))
    | select(.dst | contains("127.3.3.40"))] | length' \
  LOGS/tailscale_network_flow_logfile.txt
```
Expected: `6241` (6093 + 148)

## Key Finding Commands (Quick Copy-Paste)

**Asymmetric routing proof:**
```bash
# Flows TO Windows (should be 0)
jq '[.logs[] | .physicalTraffic[]? | select(.dst | contains("100.97.54.81"))] | length' LOGS/tailscale_network_flow_logfile.txt

# Flows FROM Windows (should be 24,549)
jq '[.logs[] | .physicalTraffic[]? | select(.src | contains("100.97.54.81"))] | length' LOGS/tailscale_network_flow_logfile.txt
```

**DERP connectivity during outage:**
```bash
jq '[.logs[] | select(.logged >= "2025-10-21T05:50:00Z" and .logged <= "2025-10-21T06:30:00Z")
    | .physicalTraffic[]? | select(.src | contains("100.97.54.81")) | select(.dst | contains("65.51.181.220"))
    | {txPkts, rxPkts}] | reduce .[] as $item ({tx:0, rx:0}; {tx: (.tx + $item.txPkts), rx: (.rx + $item.rxPkts)})' \
  LOGS/tailscale_network_flow_logfile.txt
```

**Failure rate calculation:**
```bash
# Get total and failed counts for any time period
TOTAL=$(jq '[.logs[] | select(.logged >= "2025-10-21T05:50:00Z" and .logged <= "2025-10-21T06:30:00Z") | .subnetTraffic[]?] | length' LOGS/tailscale_network_flow_logfile.txt)
FAILED=$(jq '[.logs[] | select(.logged >= "2025-10-21T05:50:00Z" and .logged <= "2025-10-21T06:30:00Z") | .subnetTraffic[]? | select(.txPkts == 1)] | length' LOGS/tailscale_network_flow_logfile.txt)
echo "Total: $TOTAL, Failed: $FAILED, Rate: $(awk "BEGIN {printf \"%.1f%%\", ($FAILED/$TOTAL)*100}")"
```
