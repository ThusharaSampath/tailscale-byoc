#!/bin/bash

# Query flows between two IPs in Tailscale network flow logs
# Usage: ./query_flows_between_ips.sh <src_ip> <dst_ip>

LOGFILE="LOGS/tailscale_network_flow_logfile.txt"

if [ $# -ne 2 ]; then
    echo "Usage: $0 <source_ip> <destination_ip>"
    echo ""
    echo "Examples:"
    echo "  $0 100.97.54.81 65.51.181.220    # Windows VM to DERP relay"
    echo "  $0 100.85.22.116 172.16.4.207    # Client to database"
    echo "  $0 100.108.154.52 172.16.20.88   # Client to database"
    echo ""
    exit 1
fi

SRC_IP="$1"
DST_IP="$2"

echo "================================================================================"
echo "Searching for flows: $SRC_IP -> $DST_IP"
echo "================================================================================"
echo ""

# Search in subnetTraffic
echo "SUBNET TRAFFIC:"
echo "---------------"
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
      proto: .proto,
      txPkts: .txPkts,
      txBytes: .txBytes
    }
' "$LOGFILE" | head -20

echo ""
echo "Count:"
jq --arg src "$SRC_IP" --arg dst "$DST_IP" '
  [.logs[] | .subnetTraffic[]? 
   | select(.src | contains($src)) 
   | select(.dst | contains($dst))] 
  | length
' "$LOGFILE"

echo ""
echo "================================================================================"

# Search in physicalTraffic
echo "PHYSICAL TRAFFIC:"
echo "-----------------"
jq --arg src "$SRC_IP" --arg dst "$DST_IP" '
  .logs[] 
  | select(.logged != null) as $log
  | .physicalTraffic[]? 
  | select(.src | contains($src)) 
  | select(.dst | contains($dst))
  | {
      time: $log.logged,
      src: .src,
      dst: .dst,
      txPkts: .txPkts,
      txBytes: .txBytes,
      rxPkts: .rxPkts,
      rxBytes: .rxBytes
    }
' "$LOGFILE" | head -20

echo ""
echo "Count:"
jq --arg src "$SRC_IP" --arg dst "$DST_IP" '
  [.logs[] | .physicalTraffic[]? 
   | select(.src | contains($src)) 
   | select(.dst | contains($dst))] 
  | length
' "$LOGFILE"

echo ""
echo "================================================================================"
