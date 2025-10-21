#!/usr/bin/env python3
"""
Gradual SQL Server connection test - creates connections one by one
This helps identify exactly when the connection limit is hit
Usage: python3 test-mssql-gradual.py <server> <database> <username> <password> [port] [max_connections] [delay]
"""

import sys
import pymssql
import time
import datetime

class ConnectionTracker:
    """Track and hold multiple database connections"""
    def __init__(self):
        self.connections = []
        self.successful = 0
        self.failed = 0

    def add_connection(self, conn_id, server, database, username, password, port=1433):
        """Attempt to create and store a new connection"""
        try:
            print(f"\n[{conn_id:3d}] Attempting connection...")
            start_time = time.time()

            conn = pymssql.connect(
                server=f"{server}:{port}",
                database=database,
                user=username,
                password=password,
                timeout=10
            )

            connect_time = (time.time() - start_time) * 1000

            # Execute query to get session ID
            cursor = conn.cursor()
            cursor.execute("SELECT @@SPID as SessionID, GETDATE() as ConnTime")
            row = cursor.fetchone()
            session_id = row[0]
            cursor.close()

            self.connections.append({
                'id': conn_id,
                'conn': conn,
                'session_id': session_id,
                'created_at': datetime.datetime.now()
            })

            self.successful += 1
            print(f"[{conn_id:3d}] ✓ SUCCESS - Session {session_id} - {connect_time:.1f}ms")
            print(f"      Total active connections: {len(self.connections)}")

            return True

        except pymssql.Error as e:
            self.failed += 1
            error_msg = str(e)
            print(f"[{conn_id:3d}] ✗ FAILED - Database error")
            print(f"      Error: {error_msg}")
            print(f"      Total active connections: {len(self.connections)}")
            return False

        except Exception as e:
            self.failed += 1
            print(f"[{conn_id:3d}] ✗ FAILED - Unexpected error")
            print(f"      Error: {e}")
            print(f"      Total active connections: {len(self.connections)}")
            return False

    def close_all(self):
        """Close all connections"""
        print(f"\n\nClosing all {len(self.connections)} connections...")
        closed = 0
        for conn_info in self.connections:
            try:
                conn_info['conn'].close()
                closed += 1
                if closed % 10 == 0:
                    print(f"  Closed {closed}/{len(self.connections)} connections...")
            except:
                pass
        print(f"✓ Closed {closed} connections")
        return closed

def test_gradual_connections(server, database, username, password, port=1433, max_connections=100, delay=2):
    """Create connections gradually one by one"""
    print("=" * 70)
    print("=== Gradual Connection Test ===")
    print("=" * 70)
    print(f"Target:              {server}:{port}")
    print(f"Database:            {database}")
    print(f"Username:            {username}")
    print(f"Max connections:     {max_connections}")
    print(f"Delay per conn:      {delay}s")
    print(f"Start time:          {datetime.datetime.now()}")
    print("=" * 70)
    print()
    print("Creating connections one by one...")
    print("Watch for the point where connections start failing.")
    print()

    tracker = ConnectionTracker()
    start_time = time.time()

    first_failure = None
    consecutive_failures = 0
    max_consecutive_failures = 3

    try:
        for i in range(1, max_connections + 1):
            success = tracker.add_connection(i, server, database, username, password, port)

            if not success:
                if first_failure is None:
                    first_failure = i
                    print(f"\n⚠️  FIRST FAILURE at connection #{i}")
                    print(f"    Active connections when failure occurred: {len(tracker.connections)}")

                consecutive_failures += 1

                if consecutive_failures >= max_consecutive_failures:
                    print(f"\n⚠️  {max_consecutive_failures} consecutive failures detected.")
                    print(f"    Connection limit appears to be around {len(tracker.connections)} connections")
                    print(f"    Stopping test...")
                    break
            else:
                consecutive_failures = 0  # Reset on success

            # Progress markers
            if i % 10 == 0:
                elapsed = int(time.time() - start_time)
                print(f"\n--- Progress: {i}/{max_connections} attempts ({elapsed}s elapsed) ---")
                print(f"    Active: {len(tracker.connections)}, Success: {tracker.successful}, Failed: {tracker.failed}")
                print()

            # Delay before next connection
            if i < max_connections:
                time.sleep(delay)

    except KeyboardInterrupt:
        print("\n\n⚠️  Test interrupted by user")

    # Hold connections for a moment to verify stability
    if len(tracker.connections) > 0:
        print(f"\n\n⏸️  Holding all {len(tracker.connections)} connections for 10 seconds...")
        print("   Use this time to check Tailscale logs or system stats")
        time.sleep(10)

    # Close all connections
    tracker.close_all()

    # Final statistics
    elapsed_total = int(time.time() - start_time)

    print()
    print("=" * 70)
    print("=== Test Results ===")
    print("=" * 70)
    print(f"End time:            {datetime.datetime.now()}")
    print(f"Total duration:      {elapsed_total//60}m {elapsed_total%60}s")
    print()
    print(f"Connection attempts: {tracker.successful + tracker.failed}")
    print(f"Successful:          {tracker.successful}")
    print(f"Failed:              {tracker.failed}")

    if first_failure:
        print()
        print(f"📊 Key Finding:")
        print(f"   First failure at:     Connection #{first_failure}")
        print(f"   Active connections:   {len(tracker.connections)} when first failure occurred")
        print(f"   Maximum achieved:     {tracker.successful} concurrent connections")
    else:
        print()
        print(f"✓ All {tracker.successful} connections succeeded!")
        print(f"  No connection limit hit within {max_connections} connections")

    if tracker.failed > 0:
        success_rate = (tracker.successful * 100) / (tracker.successful + tracker.failed)
        print(f"   Success rate:         {success_rate:.1f}%")

    print("=" * 70)

    return 0

if __name__ == "__main__":
    if len(sys.argv) < 5:
        print("Usage: python3 test-mssql-gradual.py <server> <database> <username> <password> [port] [max_connections] [delay]")
        print()
        print("Arguments:")
        print("  server          - Database server IP/hostname")
        print("  database        - Database name")
        print("  username        - Database username")
        print("  password        - Database password")
        print("  port            - Database port (default: 1433)")
        print("  max_connections - Maximum connections to attempt (default: 100)")
        print("  delay           - Seconds between connections (default: 2)")
        print()
        print("Examples:")
        print("  python3 test-mssql-gradual.py 172.16.20.88 master sa MyPass123")
        print("  python3 test-mssql-gradual.py 172.16.20.88 master sa MyPass123 1433")
        print("  python3 test-mssql-gradual.py 172.16.20.88 master sa MyPass123 1433 150 1")
        print()
        print("This test:")
        print("  - Creates connections one by one (not in parallel)")
        print("  - Shows exactly when the limit is hit")
        print("  - Holds all connections to verify stability")
        print("  - Waits 10 seconds before cleanup (time to check logs)")
        sys.exit(1)

    server = sys.argv[1]
    database = sys.argv[2]
    username = sys.argv[3]
    password = sys.argv[4]
    port = int(sys.argv[5]) if len(sys.argv) > 5 else 1433
    max_connections = int(sys.argv[6]) if len(sys.argv) > 6 else 100
    delay = float(sys.argv[7]) if len(sys.argv) > 7 else 2

    sys.exit(test_gradual_connections(server, database, username, password, port, max_connections, delay))
