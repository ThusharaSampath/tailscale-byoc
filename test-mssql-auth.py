import sys
import pymssql
import time
import datetime

def test_mssql_connection_health(server, database, username, password, port=1433, duration_minutes=10, query_interval_ms=5000):
    """Test MSSQL connection health with continuous queries"""
    print(f"=== Database Connection Health Test ===")
    print(f"Target: {server}:{port}")
    print(f"Database: {database}")
    print(f"Username: {username}")
    print(f"Duration: {duration_minutes} minutes")
    print(f"Query interval: {query_interval_ms}ms")
    print(f"Start time: {datetime.datetime.now()}")
    print()

    # Convert milliseconds to seconds for sleep
    query_interval = query_interval_ms / 1000.0

    conn = None
    success_count = 0
    failed_count = 0
    total_queries = 0
    test_duration = duration_minutes * 60  # Convert minutes to seconds
    start_time = time.time()
    end_time = start_time + test_duration

    try:
        # Initial connection
        print("Establishing initial connection...")
        conn = pymssql.connect(
            server=f"{server}:{port}",
            database=database,
            user=username,
            password=password,
            timeout=10
        )
        print("✓ Initial connection successful!")
        print()

        while time.time() < end_time:
            total_queries += 1
            query_start = time.time()
            
            try:
                cursor = conn.cursor()
                # Simple health check query
                cursor.execute("SELECT GETDATE() as CurrentTime, @@SPID as SessionID")
                row = cursor.fetchone()
                cursor.close()
                
                query_time = (time.time() - query_start) * 1000  # Convert to milliseconds
                success_count += 1
                
                elapsed_minutes = int((time.time() - start_time) / 60)
                remaining_minutes = int((end_time - time.time()) / 60)
                
                print(f"[{total_queries:3d}] ✓ SUCCESS - {query_time:.1f}ms - Time: {row[0]} - Session: {row[1]} - Elapsed: {elapsed_minutes}m - Remaining: {remaining_minutes}m")
                
            except pymssql.Error as e:
                failed_count += 1
                print(f"[{total_queries:3d}] ✗ QUERY FAILED - {e}")
                
                # Try to reconnect
                try:
                    print("    Attempting to reconnect...")
                    if conn:
                        conn.close()
                    conn = pymssql.connect(
                        server=f"{server}:{port}",
                        database=database,
                        user=username,
                        password=password,
                        timeout=10
                    )
                    print("    ✓ Reconnection successful")
                except Exception as reconnect_error:
                    print(f"    ✗ Reconnection failed: {reconnect_error}")
                    
            except Exception as e:
                failed_count += 1
                print(f"[{total_queries:3d}] ✗ UNEXPECTED ERROR - {e}")

            # Show periodic statistics every N queries based on interval
            queries_per_minute = int(60000 / query_interval_ms)  # Calculate based on milliseconds
            if queries_per_minute > 0 and total_queries % (queries_per_minute * 5) == 0:  # Every 5 minutes
                success_rate = (success_count * 100) // total_queries if total_queries > 0 else 0
                elapsed_time = int(time.time() - start_time)
                print()
                print(f"--- Statistics after {total_queries} queries ({elapsed_time//60}m {elapsed_time%60}s) ---")
                print(f"Successful: {success_count} | Failed: {failed_count} | Success Rate: {success_rate}%")
                print()

            # Wait for next query (unless we're at the end)
            if time.time() < end_time - query_interval:
                time.sleep(query_interval)

    except KeyboardInterrupt:
        print("\n\nTest interrupted by user")
    except Exception as e:
        print(f"\n✗ Fatal error: {e}")
    finally:
        if conn:
            try:
                conn.close()
                print("✓ Connection closed")
            except:
                pass

    # Final statistics
    elapsed_total = int(time.time() - start_time)
    success_rate = (success_count * 100) // total_queries if total_queries > 0 else 0
    
    print()
    print("=== Test Complete ===")
    print(f"End time: {datetime.datetime.now()}")
    print(f"Total duration: {elapsed_total//60}m {elapsed_total%60}s")
    print(f"Total queries: {total_queries}")
    print(f"Successful: {success_count}")
    print(f"Failed: {failed_count}")
    print(f"Success rate: {success_rate}%")
    
    return 0 if failed_count == 0 else 1

if __name__ == "__main__":
    if len(sys.argv) < 5:
        print("Usage: python3 test-mssql-auth.py <server> <database> <username> <password> [port] [duration_minutes] [query_interval_ms]")
        print()
        print("Arguments:")
        print("  server            - Database server IP/hostname")
        print("  database          - Database name")
        print("  username          - Database username")
        print("  password          - Database password")
        print("  port              - Database port (default: 1433)")
        print("  duration_minutes  - Test duration in minutes (default: 10)")
        print("  query_interval_ms - Milliseconds between queries (default: 5000)")
        print()
        print("Examples:")
        print("  python3 test-mssql-auth.py 172.16.4.207 master sa MyPassword123")
        print("  python3 test-mssql-auth.py 172.16.4.207 master sa MyPassword123 1433")
        print("  python3 test-mssql-auth.py 172.16.4.207 master sa MyPassword123 1433 15")
        print("  python3 test-mssql-auth.py 172.16.4.207 master sa MyPassword123 1433 15 2000")
        sys.exit(1)

    server = sys.argv[1]
    database = sys.argv[2]
    username = sys.argv[3]
    password = sys.argv[4]
    port = int(sys.argv[5]) if len(sys.argv) > 5 else 1433
    duration_minutes = int(sys.argv[6]) if len(sys.argv) > 6 else 10
    query_interval_ms = int(sys.argv[7]) if len(sys.argv) > 7 else 5000

    sys.exit(test_mssql_connection_health(server, database, username, password, port, duration_minutes, query_interval_ms))
