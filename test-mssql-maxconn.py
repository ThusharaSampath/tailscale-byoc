#!/usr/bin/env python3
"""
Test SQL Server maximum concurrent connections through Tailscale
This script creates many parallel connections to find the connection limit
Usage: python3 test-mssql-maxconn.py <server> <database> <username> <password> [port] [max_connections]
"""

import sys
import pymssql
import threading
import time
import datetime

# Global counters
lock = threading.Lock()
active_connections = 0
successful_connections = 0
failed_connections = 0
max_concurrent_reached = 0
connection_errors = []

def connection_worker(worker_id, server, database, username, password, port, hold_time):
    """Worker thread that creates and holds a connection"""
    global active_connections, successful_connections, failed_connections, max_concurrent_reached

    conn = None
    try:
        # Attempt connection
        conn = pymssql.connect(
            server=f"{server}:{port}",
            database=database,
            user=username,
            password=password,
            timeout=10
        )

        with lock:
            active_connections += 1
            successful_connections += 1
            if active_connections > max_concurrent_reached:
                max_concurrent_reached = active_connections
            current_active = active_connections

        # Execute a simple query to ensure connection is fully established
        cursor = conn.cursor()
        cursor.execute("SELECT @@SPID as SessionID, GETDATE() as ConnTime")
        row = cursor.fetchone()
        session_id = row[0]
        cursor.close()

        print(f"[Worker {worker_id:3d}] ✓ Connected (Session {session_id}) - Active: {current_active}")

        # Hold the connection open
        time.sleep(hold_time)

    except pymssql.Error as e:
        with lock:
            failed_connections += 1
            error_msg = str(e)
            if error_msg not in [err[1] for err in connection_errors]:
                connection_errors.append((worker_id, error_msg))
        print(f"[Worker {worker_id:3d}] ✗ Connection failed: {e}")

    except Exception as e:
        with lock:
            failed_connections += 1
        print(f"[Worker {worker_id:3d}] ✗ Unexpected error: {e}")

    finally:
        if conn:
            try:
                conn.close()
                with lock:
                    active_connections -= 1
                    current_active = active_connections
                print(f"[Worker {worker_id:3d}] Connection closed - Active: {current_active}")
            except:
                pass

def test_max_connections(server, database, username, password, port=1433, max_connections=200):
    """Test maximum concurrent connections"""
    print("=== SQL Server Maximum Connection Test ===")
    print(f"Target: {server}:{port}")
    print(f"Database: {database}")
    print(f"Username: {username}")
    print(f"Start time: {datetime.datetime.now()}")
    print()

    # Test parameters
    max_threads = max_connections  # Maximum number of connections to attempt
    batch_size = 10    # Create connections in batches
    batch_delay = 2    # Seconds between batches
    hold_time = 30     # Seconds to hold each connection

    print(f"Configuration:")
    print(f"  Max connections: {max_threads}")
    print(f"  Batch size: {batch_size}")
    print(f"  Batch delay: {batch_delay}s")
    print(f"  Hold time: {hold_time}s")
    print()

    threads = []
    start_time = time.time()

    try:
        # Create connections in batches
        for batch_start in range(0, max_threads, batch_size):
            batch_end = min(batch_start + batch_size, max_threads)

            print(f"\n--- Starting batch: Workers {batch_start+1} to {batch_end} ---")

            # Start batch of worker threads
            for worker_id in range(batch_start, batch_end):
                thread = threading.Thread(
                    target=connection_worker,
                    args=(worker_id + 1, server, database, username, password, port, hold_time),
                    daemon=False
                )
                thread.start()
                threads.append(thread)
                time.sleep(0.1)  # Small delay between individual connections

            # Show current status
            time.sleep(1)
            with lock:
                print(f"Status: Active={active_connections}, Success={successful_connections}, Failed={failed_connections}, Max={max_concurrent_reached}")

            # Check if we're hitting failures
            with lock:
                if failed_connections > successful_connections * 0.5:  # More than 50% failure rate
                    print(f"\n⚠️  High failure rate detected. Stopping test.")
                    break

            # Wait before next batch
            if batch_end < max_threads:
                time.sleep(batch_delay)

    except KeyboardInterrupt:
        print("\n\n⚠️  Test interrupted by user")
    
    finally:
        # Wait for all threads to complete
        print(f"\n--- Waiting for all connections to close (up to {hold_time + 10}s) ---")
        for thread in threads:
            thread.join(timeout=hold_time + 10)

    # Final statistics
    elapsed_total = int(time.time() - start_time)

    print()
    print("=" * 60)
    print("=== Test Complete ===")
    print(f"End time: {datetime.datetime.now()}")
    print(f"Total duration: {elapsed_total//60}m {elapsed_total%60}s")
    print()
    print("Results:")
    print(f"  Total connection attempts: {successful_connections + failed_connections}")
    print(f"  Successful connections: {successful_connections}")
    print(f"  Failed connections: {failed_connections}")
    print(f"  Maximum concurrent connections: {max_concurrent_reached}")

    if successful_connections > 0:
        success_rate = (successful_connections * 100) / (successful_connections + failed_connections)
        print(f"  Success rate: {success_rate:.1f}%")

    if connection_errors:
        print()
        print("Connection Errors (unique):")
        for worker_id, error in connection_errors[:10]:  # Show first 10 unique errors
            print(f"  [Worker {worker_id}] {error}")
        if len(connection_errors) > 10:
            print(f"  ... and {len(connection_errors) - 10} more error types")

    print("=" * 60)

    return 0

if __name__ == "__main__":
    if len(sys.argv) < 5:
        print("Usage: python3 test-mssql-maxconn.py <server> <database> <username> <password> [port] [max_connections]")
        print()
        print("Arguments:")
        print("  server          - Database server IP/hostname")
        print("  database        - Database name")
        print("  username        - Database username")
        print("  password        - Database password")
        print("  port            - Database port (default: 1433)")
        print("  max_connections - Maximum connections to test (default: 200)")
        print()
        print("Examples:")
        print("  python3 test-mssql-maxconn.py 172.16.4.207 master sa MyPassword123")
        print("  python3 test-mssql-maxconn.py 172.16.4.207 master sa MyPassword123 1433")
        print("  python3 test-mssql-maxconn.py 172.16.4.207 master sa MyPassword123 1433 500")
        print()
        print("This script will:")
        print("  - Create up to N concurrent connections (default: 200)")
        print("  - Create connections in batches of 10")
        print("  - Hold each connection for 30 seconds")
        print("  - Report the maximum concurrent connections achieved")
        sys.exit(1)

    server = sys.argv[1]
    database = sys.argv[2]
    username = sys.argv[3]
    password = sys.argv[4]
    port = int(sys.argv[5]) if len(sys.argv) > 5 else 1433
    max_connections = int(sys.argv[6]) if len(sys.argv) > 6 else 200

    sys.exit(test_max_connections(server, database, username, password, port, max_connections))
