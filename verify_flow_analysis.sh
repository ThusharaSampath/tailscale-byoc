#!/bin/bash

# Verification script for Tailscale network flow analysis
# Run this to verify all key findings from asymmetric_routing_analysis.txt

LOGFILE="LOGS/tailscale_network_flow_logfile.txt"

echo "================================================================================"
echo "TAILSCALE NETWORK FLOW VERIFICATION"
echo "================================================================================"
echo ""
echo "File: $LOGFILE"
echo ""

# Test 1: Smoking gun - zero inbound flows
echo "1. SMOKING GUN - Inbound flows to Windows VM (100.97.54.81)"
echo "   Expected: 0"
inbound=$(jq '[.logs[] | .subnetTraffic[]?, .physicalTraffic[]? | select(.dst | contains("100.97.54.81"))] | length' "$LOGFILE")
echo "   Actual: $inbound"
if [ "$inbound" -eq 0 ]; then
    echo "   ✓ CONFIRMED: Asymmetric routing (no inbound)"
else
    echo "   ✗ UNEXPECTED: Found inbound flows"
fi
echo ""

# Test 2: Outbound flows from Windows
echo "2. Outbound flows FROM Windows VM (100.97.54.81)"
echo "   Expected: ~24,549"
outbound=$(jq '[.logs[] | .subnetTraffic[]?, .physicalTraffic[]? | select(.src | contains("100.97.54.81"))] | length' "$LOGFILE")
echo "   Actual: $outbound"
if [ "$outbound" -gt 20000 ]; then
    echo "   ✓ CONFIRMED: Windows can send (asymmetric)"
else
    echo "   ✗ UNEXPECTED: Low outbound count"
fi
echo ""

# Test 3: DERP connectivity during outage
echo "3. DERP connectivity during outage (05:50-06:30)"
echo "   Expected: TX ~18,197, RX ~17,673"
derp=$(jq '.logs[] | select(.logged >= "2025-10-21T05:50:00Z" and .logged <= "2025-10-21T06:30:00Z")
    | .physicalTraffic[]?
    | select(.src | contains("100.97.54.81") and .dst | contains("65.51.181.220"))
    | {txPkts, rxPkts}' "$LOGFILE" | \
    jq -s 'reduce .[] as $item ({tx:0, rx:0}; {tx: (.tx + $item.txPkts), rx: (.rx + $item.rxPkts)})')
echo "   Actual: $derp"
rx=$(echo "$derp" | jq '.rx')
if [ "$rx" -gt 15000 ]; then
    echo "   ✓ CONFIRMED: Control plane active (but data plane broken)"
else
    echo "   ✗ UNEXPECTED: Low RX packets"
fi
echo ""

# Test 4: Failure rate during outage
echo "4. Failure rate during outage (05:50-06:30)"
total=$(jq '[.logs[] | select(.logged >= "2025-10-21T05:50:00Z" and .logged <= "2025-10-21T06:30:00Z")
    | .subnetTraffic[]?] | length' "$LOGFILE")
failed=$(jq '[.logs[] | select(.logged >= "2025-10-21T05:50:00Z" and .logged <= "2025-10-21T06:30:00Z")
    | .subnetTraffic[]?
    | select(.txPkts == 1)] | length' "$LOGFILE")
echo "   Total flows: $total"
echo "   Failed (single-pkt): $failed"
if [ "$total" -gt 0 ]; then
    failure_rate=$(awk "BEGIN {printf \"%.1f\", ($failed/$total)*100}")
    echo "   Failure rate: ${failure_rate}%"
    echo "   Expected: ~98.5%"
    if (( $(echo "$failure_rate > 95" | bc -l) )); then
        echo "   ✓ CONFIRMED: Extremely high failure rate"
    else
        echo "   ✗ UNEXPECTED: Lower failure rate"
    fi
else
    echo "   ✗ ERROR: No flows found"
fi
echo ""

# Test 5: Time-based comparison
echo "5. Success rates across time periods"
echo ""
echo "   BEFORE outage (<05:50):"
before_total=$(jq '[.logs[] | select(.logged < "2025-10-21T05:50:00Z") | .subnetTraffic[]?] | length' "$LOGFILE")
before_failed=$(jq '[.logs[] | select(.logged < "2025-10-21T05:50:00Z") | .subnetTraffic[]? | select(.txPkts == 1)] | length' "$LOGFILE")
before_rate=$(awk "BEGIN {printf \"%.1f\", ($before_failed/$before_total)*100}")
echo "     Total: $before_total, Failed: $before_failed, Rate: ${before_rate}%"

echo "   DURING outage (05:50-06:30):"
during_total=$total
during_failed=$failed
during_rate=$(awk "BEGIN {printf \"%.1f\", ($during_failed/$during_total)*100}")
echo "     Total: $during_total, Failed: $during_failed, Rate: ${during_rate}%"

echo "   AFTER outage (>06:30):"
after_total=$(jq '[.logs[] | select(.logged > "2025-10-21T06:30:00Z") | .subnetTraffic[]?] | length' "$LOGFILE")
after_failed=$(jq '[.logs[] | select(.logged > "2025-10-21T06:30:00Z") | .subnetTraffic[]? | select(.txPkts == 1)] | length' "$LOGFILE")
after_rate=$(awk "BEGIN {printf \"%.1f\", ($after_failed/$after_total)*100}")
echo "     Total: $after_total, Failed: $after_failed, Rate: ${after_rate}%"

echo ""
if (( $(echo "$after_rate > 90" | bc -l) )); then
    echo "   ⚠️  WARNING: Even after 'recovery' failure rate is ${after_rate}%"
    echo "   This indicates CHRONIC routing issues, not just acute outage"
fi
echo ""

# Test 6: What Windows communicates with
echo "6. Windows VM destinations (should only be DERP relays)"
echo "   Expected: Only 65.51.181.220:41641 and 127.3.3.40:*"
echo "   Actual destinations:"
jq '.logs[] | .physicalTraffic[]? | select(.src | contains("100.97.54.81")) | .dst' "$LOGFILE" | \
    sort -u | sed 's/^/     /'
echo ""

# Test 7: Sample failed flow
echo "7. Sample FAILED flow (single packet = SYN only)"
jq '.logs[] | select(.logged >= "2025-10-21T05:50:00Z" and .logged <= "2025-10-21T06:30:00Z")
    | .subnetTraffic[]?
    | select(.txPkts == 1 and (.dst | contains("172.16")))' "$LOGFILE" | head -1
echo ""

# Test 8: Sample successful flow
echo "8. Sample SUCCESSFUL flow (multi-packet)"
jq '.logs[] | .subnetTraffic[]? | select(.txPkts > 1 and (.dst | contains("172.16")))' "$LOGFILE" | head -1
echo ""

echo "================================================================================"
echo "SUMMARY"
echo "================================================================================"
echo ""
echo "Key findings:"
echo "  1. Asymmetric routing: $inbound inbound vs $outbound outbound flows"
echo "  2. Control plane active during outage (DERP RX: $rx pkts)"
echo "  3. Data plane broken during outage (${during_rate}% failure)"
echo "  4. Chronic issue persists after outage (${after_rate}% failure)"
echo ""
echo "ROOT CAUSE: Windows VM in 'send-only' mode"
echo "  - Can send to DERP (control plane)"
echo "  - Cannot receive inbound traffic (data plane blocked)"
echo "  - Most likely: Windows Firewall blocking inbound Tailscale"
echo ""
echo "See asymmetric_routing_analysis.txt for detailed analysis and recovery steps."
echo ""
echo "================================================================================"
