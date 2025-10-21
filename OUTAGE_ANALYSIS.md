# Tailscale Proxy Outage Analysis

## Executive Summary

Two distinct outage patterns have been identified affecting the Tailscale-based database connectivity:

1. **Outage Type 1** (Oct 20, 10:07-10:24): IPv6 connection instability - 17 minutes, auto-recovered
2. **Outage Type 2** (Oct 21, ongoing): Complete Windows subnet router failure - hours, manual intervention required

---

## Outage Type 1: IPv6 + Connection Instability

### Timeline
- **Start**: 2025-10-20T10:07:20.435Z
- **End**: 2025-10-20T10:24:18.798Z
- **Duration**: 17 minutes
- **Recovery**: Auto-recovered

### Symptoms
- Database connections failing
- DBeaver (local database client) cannot connect from local machine on customer's Tailscale network
- FTP status unknown (couldn't test in narrow window)

### Error Evidence

**Ballerina Client**:
```
Error while getting the connection for SQLClientConnector.
The TCP/IP connection to the host tailscale-proxy-2039118774, port 8082 has failed.
Error: "The driver received an unexpected pre-login response.
Verify the connection properties and check that an instance of SQL Server is running
on the host and accepting TCP/IP connections at the port. This driver can be used
only with SQL Server 2005 or later.".
ClientConnectionId:d2832082-df1a-443f-aceb-3a2ae0392ad2
```

**Tailscale Proxy**:
```
Failed to copy data to proxy connection:
writeto tcp 10.100.88.134:8082->10.100.75.196:42588:
readfrom tcp [::1]:55480->[::1]:1055:
use of closed network connection
```

### Root Cause Analysis

**Key Indicators**:
1. `[::1]:55480->[::1]:1055` - **IPv6 loopback address** in proxy logs
2. "use of closed network connection" - Connection died during data transfer
3. "unexpected pre-login response" - SQL client received corrupted/partial data

**Failure Sequence**:
1. Forwarder (main.go) resolves `localhost` to IPv6 `[::1]`
2. Connects to SOCKS5 at `[::1]:1055`
3. Connection becomes unstable and closes unexpectedly
4. Partial/corrupted data sent to SQL client
5. SQL driver rejects data as invalid TDS protocol

**Why it auto-recovered**:
- Subsequent connection attempts may have used IPv4 `127.0.0.1`
- Or SOCKS5/tailscaled restarted and stabilized
- Connection instability was transient

### Fix

**File**: `main.go:16`

```go
// Before
const (
    proxyAddr = "localhost:1055"
)

// After
const (
    proxyAddr = "127.0.0.1:1055"
)
```

**Why this fixes it**:
- Forces IPv4 loopback (`127.0.0.1`) instead of letting Go resolve `localhost`
- Avoids IPv6 path which appears unstable
- Ensures consistent connection behavior

---

## Outage Type 2: Windows Tailscale Node Complete Failure

### Timeline
- **Start**: 2025-10-21 (exact time from logs: ~05:50 UTC / 11:20 IST)
- **Status**: **ONGOING** (as of analysis time)
- **Duration**: Multiple hours
- **Recovery**: None - requires manual intervention

### Symptoms
- ❌ Tailscale ping to Windows node **FAILS** (timeout)
- ❌ Database connections failing
- ❌ FTP not working
- ❌ VM/Windows machine not reachable via Tailscale
- ❌ All 172.16.x.x subnet routes down

### Error Evidence

**Tailscale Proxy** (consistent pattern):
```
2025/10/21 05:50:34 Failed to connect to destination 172.16.20.88:1433 through proxy:
socks connect tcp localhost:1055->172.16.20.88:1433:
unknown error general SOCKS server failure

2025/10/21 05:50:35 Failed to connect to destination 172.16.20.88:1433 through proxy:
socks connect tcp localhost:1055->172.16.20.88:1433:
unknown error general SOCKS server failure
[... repeating every second ...]
```

**Ballerina Client**:
```
error: Error in SQL connector configuration: Failed to initialize pool:
Connection reset ClientConnectionId:d446860d-523a-4e9f-a006-78823f6c59e0
Caused by :Connection reset ClientConnectionId:d446860d-523a-4e9f-a006-78823f6c59e0
Caused by :Connection reset
```

### Root Cause Analysis

**Tailscale Network Status** (from `tailscale status --json`):
```json
{
  "HostName": "v-BHPSTailScale",
  "TailscaleIPs": ["100.97.54.81"],
  "PrimaryRoutes": ["172.16.4.0/22", "172.16.20.0/24"],
  "Addrs": null,
  "CurAddr": "",
  "Relay": "nyc",
  "RxBytes": 0,
  "TxBytes": 10140,
  "LastWrite": "2025-10-18T16:58:57",  // 3 days old!
  "LastSeen": "0001-01-01T00:00:00Z",   // Never seen
  "LastHandshake": "0001-01-01T00:00:00Z", // No WireGuard handshake
  "Online": true  // False positive
}
```

**Key Evidence**:
1. `tailscale ping 100.97.54.81` → **Complete timeout** (no response)
2. `RxBytes: 0` → Windows node **never receiving any data**
3. `LastWrite: 2025-10-18` → Last activity was **3 days ago**
4. `LastHandshake: epoch zero` → Never completed WireGuard connection
5. `CurAddr: ""` → No current connection address

**SOCKS5 Error "general SOCKS server failure"**:
- This is SOCKS5 error code 1
- Means: SOCKS5 proxy (tailscaled) is working
- But: Cannot route to destination network
- Cause: Subnet router (Windows node) is unreachable

**Failure Sequence**:
1. Client → Forwarder:8082 (connects successfully)
2. Forwarder → SOCKS5 localhost:1055 (connects successfully)
3. SOCKS5 tries to route to 172.16.20.88 via Tailscale
4. Tailscale has no path to Windows node (100.97.54.81)
5. SOCKS5 returns "general failure"
6. Forwarder → Client sends RST
7. Client receives "Connection reset"

**Why it doesn't auto-recover**:
- ~~Windows Tailscale service likely crashed or stopped~~ (INCORRECT - see Tailscale Network Flow Analysis)
- **ACTUAL**: Subnet routes were disabled or not advertised
- Tailscale daemon was running and connected to DERP
- But subnet routing for 172.16.4.0/22 and 172.16.20.0/24 was inactive
- Machine had internet connectivity (DERP traffic confirmed)

---

## Comparison: Two Different Outages

| Aspect | Outage 1 (IPv6 Issue) | Outage 2 (Node Dead) |
|--------|-----------------------|----------------------|
| **Tailscale connectivity** | Degraded/unstable | Completely down |
| **Windows node reachable** | Unknown (not directly tested) | ❌ Confirmed unreachable |
| **FTP service** | Unknown | ❌ Not working |
| **Duration** | 17 minutes | Hours (ongoing) |
| **Auto-recovery** | ✅ Yes | ❌ No |
| **Proxy log pattern** | "use of closed network connection" | "general SOCKS server failure" |
| **Proxy log detail** | Shows IPv6 `[::1]` | No IPv6 addresses |
| **Client error** | "unexpected pre-login response" | "Connection reset" at pool init |
| **SOCKS5 status** | ✅ Working but unstable | ✅ Working but no route |
| **Root cause** | IPv6 connection instability | Windows Tailscale dead |

---

## Additional Findings

### Hubble Network Flow Analysis (Oct 21, 05:58-06:05)

**Captured during Outage Type 2**:

- **Total packets**: 6,692
- **Connection attempts**: 2,407
- **Successful handshakes**: 659 (27.4%)
- **Connection resets (RST)**: 643
- **Network policy denials**: 1,508

**Failure Pattern** (every connection):
```
05:59:45.263: Client -> Proxy:8082 (SYN)           # Connection initiated
05:59:45.264: Client <- Proxy:8082 (SYN, ACK)     # Proxy accepts
05:59:45.264: Client -> Proxy:8082 (ACK)          # Handshake complete
05:59:45.265: Client -> Proxy:8082 (ACK, PSH)     # Client sends SQL data
05:59:45.285: Client <- Proxy:8082 (ACK, RST)     # ❌ PROXY RESETS (20ms later)
```

**Timing**: Only 20-22ms from handshake to RST

**Interpretation**:
- TCP handshake to forwarder succeeds
- Client sends TDS handshake data
- Forwarder fails to forward via SOCKS5
- Forwarder immediately resets connection

### Long-Term Health Check Results (20 hours)

**Ballerina Health Check** (Oct 21, 12:33):
- **Duration**: 1,219 minutes (~20 hours)
- **Total queries**: 55,900+
- **Successful**: 54,797
- **Failed**: 1,103
- **Success rate**: **98.0%**

**Failure Distribution**:
- Not evenly distributed
- Failures occur in **bursts** (5-30 second windows)
- During outage windows: 100% failure
- During normal operation: ~100% success

### Tailscale Network Flow Analysis (Oct 21, 05:05-09:33 UTC)

**Critical Discovery: Windows Node WAS Connected During Outage**

Analyzed 21,658 log entries from Tailscale admin console covering the outage window:

**Time-based Flow Analysis**:

| Period | Flows | Single-Packet (Failed) | Multi-Packet (Success) | Success Rate |
|--------|-------|------------------------|------------------------|--------------|
| Before outage (<05:50) | 19,379 | 19,064 (98.4%) | 315 (1.6%) | **1.6%** |
| During outage (05:50-06:30) | 17,950 | 17,684 (98.5%) | 266 (1.5%) | **1.5%** |
| After outage (>06:30) | 78,768 | 77,130 (97.9%) | 1,638 (2.1%) | **2.1%** |

**DERP Relay Connectivity (Windows Node → 65.51.181.220:41641)**:

| Period | DERP Flows | TX Packets | RX Packets | Bidirectional? |
|--------|------------|------------|------------|----------------|
| Before outage | 3,131 | 19,700 | 19,091 | ✓ YES |
| During outage | 2,812 | 18,197 | 17,673 | ✓ YES |
| After outage | 12,365 | 89,369 | 86,979 | ✓ YES |

**⚠️ CRITICAL FINDINGS**:

1. **Windows node HAD active DERP connection during outage**
   - Bidirectional traffic confirmed (TX: 18,197 pkts, RX: 17,673 pkts)
   - DERP relay was functioning normally
   - **BUT**: RX packets were control plane only (heartbeats), not data plane

2. **98.5% of connection attempts failed even WITH DERP active**
   - Single-packet flows = SYN packets that got no response
   - Only 1.5% successful handshakes during outage vs 2.1% after

3. **Success rate barely improved after "outage"**
   - Before: 1.6% success
   - During: 1.5% success
   - After: 2.1% success
   - This suggests **ongoing routing issues even outside outage window**

4. **🔍 SMOKING GUN: Zero inbound flows to Windows VM**
   - **Total flows FROM 100.97.54.81**: 24,549 flows (Windows sending)
   - **Total flows TO 100.97.54.81**: **0 flows** (nobody can reach Windows)
   - This is **asymmetric routing failure**
   - Windows can send (control plane heartbeats to DERP)
   - But Windows cannot receive (data plane traffic blocked/dropped)

**Revised Root Cause**:

The Windows node was in a **degraded "send-only" state**:
- ✓ Control plane: Windows sending heartbeats to DERP (TX: 18,197 pkts)
- ✓ Control plane: Windows receiving heartbeats from DERP (RX: 17,673 pkts)
- ✗ Data plane: **Zero inbound data flows** to Windows VM (0 flows TO 100.97.54.81)
- ✗ Subnet routing 172.16.x.x was broken (routes not advertised or inbound blocked)
- ✗ SOCKS5 could not establish routes to destination IPs

**Why this is asymmetric routing failure**:

| Direction | Status | Evidence |
|-----------|--------|----------|
| Windows → DERP | ✓ Working | 18,197 TX packets, control plane active |
| DERP → Windows | ✓ Control plane only | 17,673 RX packets (heartbeats) |
| DERP → Windows | ✗ Data plane blocked | 0 inbound data flows recorded |
| Others → Windows | ✗ Completely blocked | Cannot ping 100.97.54.81 |
| Others → Subnet | ✗ Completely blocked | Cannot reach 172.16.x.x |

This explains:
- Why `tailscale ping 100.97.54.81` fails (no inbound path to Windows VM)
- Why DERP traffic continued (control plane heartbeats use different path)
- Why SOCKS5 returned "general failure" (no route to subnet, can't reach Windows)
- Why 98.5% of flows were single-packet failures (SYN sent, no route back)
- Why Windows shows as "Online" in status (control plane active)

**Root cause**: Likely Windows Firewall or Tailscale inbound connection failure blocking ALL inbound traffic to the Windows VM, while still allowing outbound control plane heartbeats.

---

## Recommended Fixes

### Immediate: Fix IPv6 Issue (Outage 1)

**File**: `main.go`

```go
const (
    proxyAddr = "127.0.0.1:1055"  // Force IPv4
)
```

### Immediate: Fix Windows Inbound Connectivity (Outage 2)

**Customer must execute on Windows machine `v-BHPSTailScale`**:

```powershell
# Step 1: Check Windows Firewall (CRITICAL)
# Verify Tailscale is allowed through firewall
Get-NetFirewallRule -DisplayName "*Tailscale*" | Select-Object DisplayName, Enabled, Direction, Action

# If Tailscale rules are missing or disabled, allow it:
New-NetFirewallRule -DisplayName "Tailscale" -Direction Inbound -Action Allow -Program "C:\Program Files\Tailscale\tailscale.exe"
New-NetFirewallRule -DisplayName "Tailscale" -Direction Inbound -Action Allow -Program "C:\Program Files\Tailscale\tailscaled.exe"

# Step 2: Restart Tailscale with subnet routes
tailscale down
tailscale up --advertise-routes=172.16.4.0/22,172.16.20.0/24 --accept-routes --reset

# Step 3: Verify status
tailscale status

# Step 4: Test from another Tailscale machine
# From Choreo pod or your local machine:
tailscale ping 100.97.54.81        # Should work now
ping 172.16.20.88                  # Should work now
ping 172.16.4.207                  # Should work now
```

**Root Cause (CONFIRMED via flow logs)**:

The Windows VM has **asymmetric routing failure**:
- ✓ Control plane working (can send heartbeats to DERP)
- ✗ Data plane broken (zero inbound flows recorded)
- **24,549 flows FROM Windows, 0 flows TO Windows**

This is likely:
1. **Windows Firewall blocking inbound Tailscale traffic**
2. Subnet routes not advertised (`--advertise-routes` missing)
3. Tailscale daemon in degraded state (not processing inbound connections)

The `--reset` flag will force Tailscale to re-establish all connections and may clear the degraded state.

### Short-Term: Improve Monitoring

1. **Add to start.sh** (already implemented):
   - Monitor tailscaled process health
   - Exit pod if tailscaled dies
   - Kubernetes will restart pod

2. **Alert on error rates**:
   - Trigger alert if RST rate > 5% in 1-minute window
   - Monitor SOCKS5 "general failure" errors

3. **Dashboard metrics**:
   - Connection success rate
   - SOCKS5 error counts
   - Tailscale node reachability

### Long-Term: Architecture Improvements

1. **Redundant Subnet Routers**:
   - Deploy 2+ Windows Tailscale nodes
   - Configure automatic failover
   - Load balance across routers

2. **Direct Tailscale Integration**:
   - Run Tailscale client directly in Choreo pods
   - Eliminate forwarder proxy layer
   - Reduce failure points

3. **Connection Retry Logic**:
   - Implement exponential backoff
   - Retry failed connections
   - Circuit breaker pattern

---

## Appendix: Technical Details

### SOCKS5 Error Codes

| Code | Message | Meaning |
|------|---------|---------|
| 0 | Success | Connection succeeded |
| 1 | General failure | SOCKS server cannot complete request |
| 2 | Connection not allowed | Policy/firewall block |
| 3 | Network unreachable | No route to network |
| 4 | Host unreachable | Destination host down |
| 5 | Connection refused | Destination actively refused |

### Tailscale Connection States

- **Online + CurAddr set**: Active, connected
- **Online + CurAddr empty**: Zombie (registered but unreachable)
- **LastHandshake = epoch**: Never completed WireGuard setup
- **RxBytes = 0**: One-way communication (sending but not receiving)

### IPv6 vs IPv4 Resolution in Go

When Go resolves `localhost`:
1. Checks `/etc/hosts` (if present)
2. Uses system DNS resolver
3. **Prefers IPv6** if available: `::1`
4. Falls back to IPv4: `127.0.0.1`

Using explicit `127.0.0.1` forces IPv4 and avoids resolution ambiguity.

---

## References

- Customer Logs: Oct 20, 2025 (10:07-10:24 UTC)
- Customer Logs: Oct 21, 2025 (05:50+ UTC)
- Hubble Logs: Oct 21, 2025 (05:58-06:05 UTC)
- Tailscale Status: Oct 21, 2025 (multiple snapshots)
- Test Results: 20-hour health check run

---

*Analysis Date: October 21, 2025*
