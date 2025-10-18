#!/usr/bin/env python3
"""
Realistic SQL Server workload simulation through Tailscale
Simulates real application behavior with connection pooling and random query intervals
Usage: python3 test-mssql-realistic.py <server> <database> <username> <password> [port] [duration_minutes] [min_interval] [max_interval] [pool_size]
"""

import sys
import pymssql
import threading
import time
import datetime
import random
import queue

# Global statistics
lock = threading.Lock()
total_queries = 0
successful_queries = 0
failed_queries = 0
query_times = []
connection_errors = []
start_time = None

class ConnectionPool:
    """Simple connection pool for SQL Server"""
    def __init__(self, server, database, username, password, port=1433, pool_size=10):
        self.server = server
        self.database = database
        self.username = username
        self.password = password
        self.port = port
        self.pool_size = pool_size
        self.pool = queue.Queue(maxsize=pool_size)
        self.lock = threading.Lock()
        self.active_connections = 0
        self.total_created = 0

        print(f"Initializing connection pool (size={pool_size}) to {server}:{port}...")
        for i in range(pool_size):
            try:
                conn = self._create_connection()
                self.pool.put(conn)
                print(f"  ✓ Connection {i+1}/{pool_size} created")
            except Exception as e:
                print(f"  ✗ Failed to create connection {i+1}/{pool_size}: {e}")

        print(f"✓ Connection pool ready with {self.pool.qsize()} connections\n")

    def _create_connection(self):
        """Create a new database connection"""
        with self.lock:
            self.total_created += 1

        return pymssql.connect(
            server=f"{self.server}:{self.port}",
            database=self.database,
            user=self.username,
            password=self.password,
            timeout=10
        )

    def get_connection(self, timeout=5):
        """Get a connection from the pool"""
        try:
            conn = self.pool.get(timeout=timeout)
            with self.lock:
                self.active_connections += 1
            return conn
        except queue.Empty:
            raise Exception("Connection pool exhausted - no available connections")

    def return_connection(self, conn):
        """Return a connection to the pool"""
        try:
            # Test if connection is still alive
            cursor = conn.cursor()
            cursor.execute("SELECT 1")
            cursor.close()

            self.pool.put(conn)
            with self.lock:
                self.active_connections -= 1
        except:
            # Connection is dead, create a new one
            try:
                new_conn = self._create_connection()
                self.pool.put(new_conn)
                with self.lock:
                    self.active_connections -= 1
            except Exception as e:
                print(f"⚠️  Failed to recreate dead connection: {e}")

    def close_all(self):
        """Close all connections in the pool"""
        closed = 0
        while not self.pool.empty():
            try:
                conn = self.pool.get_nowait()
                conn.close()
                closed += 1
            except:
                pass
        return closed

def query_worker(worker_id, pool, duration_seconds, min_interval, max_interval, stop_event):
    """Worker thread that executes queries at random intervals"""
    global total_queries, successful_queries, failed_queries, query_times, connection_errors

    worker_start = time.time()
    worker_queries = 0
    worker_success = 0
    worker_failed = 0

    print(f"[Worker {worker_id:2d}] Started")

    while not stop_event.is_set() and (time.time() - worker_start) < duration_seconds:
        # Random interval between queries
        interval = random.uniform(min_interval, max_interval)
        time.sleep(interval)

        if stop_event.is_set():
            break

        # Get connection from pool
        conn = None
        try:
            conn = pool.get_connection(timeout=5)
            query_start = time.time()

            # Execute realistic query
            cursor = conn.cursor()
            cursor.execute("""
                SELECT
                    GETDATE() as QueryTime,
                    @@SPID as SessionID,
                    @@VERSION as ServerVersion
            """)
            row = cursor.fetchone()
            cursor.close()

            query_duration = (time.time() - query_start) * 1000  # milliseconds

            with lock:
                total_queries += 1
                successful_queries += 1
                query_times.append(query_duration)
                worker_queries += 1
                worker_success += 1

            elapsed = int(time.time() - start_time)
            print(f"[Worker {worker_id:2d}] Query #{worker_queries:3d} ✓ {query_duration:6.1f}ms - Session {row[1]} - Elapsed: {elapsed//60}m{elapsed%60:02d}s")

        except queue.Empty:
            with lock:
                total_queries += 1
                failed_queries += 1
                worker_queries += 1
                worker_failed += 1
            print(f"[Worker {worker_id:2d}] Query #{worker_queries:3d} ✗ POOL EXHAUSTED")

        except pymssql.Error as e:
            with lock:
                total_queries += 1
                failed_queries += 1
                worker_queries += 1
                worker_failed += 1
                error_msg = str(e)
                if error_msg not in [err for err in connection_errors]:
                    connection_errors.append(error_msg)
            print(f"[Worker {worker_id:2d}] Query #{worker_queries:3d} ✗ DB ERROR: {e}")

        except Exception as e:
            with lock:
                total_queries += 1
                failed_queries += 1
                worker_queries += 1
                worker_failed += 1
            print(f"[Worker {worker_id:2d}] Query #{worker_queries:3d} ✗ ERROR: {e}")

        finally:
            if conn:
                pool.return_connection(conn)

    print(f"[Worker {worker_id:2d}] Finished - Queries: {worker_queries}, Success: {worker_success}, Failed: {worker_failed}")

def print_statistics(duration_minutes):
    """Print periodic statistics"""
    global total_queries, successful_queries, failed_queries, query_times

    elapsed = int(time.time() - start_time)

    print()
    print("=" * 70)
    print(f"Statistics at {elapsed//60}m{elapsed%60:02d}s / {duration_minutes}m")
    print("=" * 70)

    with lock:
        print(f"Total Queries:      {total_queries}")
        print(f"  Successful:       {successful_queries}")
        print(f"  Failed:           {failed_queries}")

        if total_queries > 0:
            success_rate = (successful_queries * 100) / total_queries
            print(f"  Success Rate:     {success_rate:.1f}%")

            if query_times:
                avg_time = sum(query_times) / len(query_times)
                min_time = min(query_times)
                max_time = max(query_times)
                sorted_times = sorted(query_times)
                p50 = sorted_times[len(sorted_times)//2]
                p95 = sorted_times[int(len(sorted_times)*0.95)]
                p99 = sorted_times[int(len(sorted_times)*0.99)]

                print()
                print("Query Latency (ms):")
                print(f"  Average:          {avg_time:.1f}ms")
                print(f"  Min:              {min_time:.1f}ms")
                print(f"  Max:              {max_time:.1f}ms")
                print(f"  P50 (median):     {p50:.1f}ms")
                print(f"  P95:              {p95:.1f}ms")
                print(f"  P99:              {p99:.1f}ms")

        if connection_errors:
            print()
            print("Connection Errors:")
            for error in connection_errors[:5]:
                print(f"  - {error}")
            if len(connection_errors) > 5:
                print(f"  ... and {len(connection_errors) - 5} more")

    print("=" * 70)
    print()

def test_realistic_workload(server, database, username, password, port=1433,
                           duration_minutes=10, min_interval=1.0, max_interval=5.0, pool_size=10):
    """Test realistic workload with connection pooling"""
    global start_time

    print()
    print("=" * 70)
    print("=== Realistic SQL Server Workload Simulation ===")
    print("=" * 70)
    print(f"Target:             {server}:{port}")
    print(f"Database:           {database}")
    print(f"Username:           {username}")
    print(f"Duration:           {duration_minutes} minutes")
    print(f"Query interval:     {min_interval}s - {max_interval}s (random)")
    print(f"Connection pool:    {pool_size} connections")
    print(f"Worker threads:     {pool_size} workers")
    print(f"Start time:         {datetime.datetime.now()}")
    print("=" * 70)
    print()

    start_time = time.time()
    duration_seconds = duration_minutes * 60

    try:
        # Create connection pool
        pool = ConnectionPool(server, database, username, password, port, pool_size)

        # Create worker threads
        threads = []
        stop_event = threading.Event()

        print(f"Starting {pool_size} worker threads...\n")
        for i in range(pool_size):
            thread = threading.Thread(
                target=query_worker,
                args=(i + 1, pool, duration_seconds, min_interval, max_interval, stop_event),
                daemon=False
            )
            thread.start()
            threads.append(thread)
            time.sleep(0.1)  # Stagger thread starts

        print(f"\n✓ All workers started\n")

        # Monitor progress and print statistics periodically
        stats_interval = 60  # Print stats every minute
        next_stats_time = time.time() + stats_interval

        while time.time() < start_time + duration_seconds:
            time.sleep(1)

            if time.time() >= next_stats_time:
                print_statistics(duration_minutes)
                next_stats_time = time.time() + stats_interval

        # Signal workers to stop
        print("\n⏰ Test duration reached. Stopping workers...\n")
        stop_event.set()

        # Wait for all threads to complete
        for thread in threads:
            thread.join(timeout=10)

        # Close connection pool
        print("\nClosing connection pool...")
        closed = pool.close_all()
        print(f"✓ Closed {closed} connections")

    except KeyboardInterrupt:
        print("\n\n⚠️  Test interrupted by user")
        stop_event.set()
        if pool:
            pool.close_all()

    # Final statistics
    elapsed_total = int(time.time() - start_time)

    print()
    print("=" * 70)
    print("=== FINAL RESULTS ===")
    print("=" * 70)
    print(f"End time:           {datetime.datetime.now()}")
    print(f"Total duration:     {elapsed_total//60}m {elapsed_total%60}s")
    print()

    with lock:
        print(f"Total Queries:      {total_queries}")
        print(f"  Successful:       {successful_queries}")
        print(f"  Failed:           {failed_queries}")

        if total_queries > 0:
            success_rate = (successful_queries * 100) / total_queries
            qps = total_queries / elapsed_total
            print(f"  Success Rate:     {success_rate:.1f}%")
            print(f"  Queries/second:   {qps:.2f}")

            if query_times:
                avg_time = sum(query_times) / len(query_times)
                sorted_times = sorted(query_times)
                p50 = sorted_times[len(sorted_times)//2]
                p95 = sorted_times[int(len(sorted_times)*0.95)]
                p99 = sorted_times[int(len(sorted_times)*0.99)]

                print()
                print("Query Latency:")
                print(f"  Average:          {avg_time:.1f}ms")
                print(f"  P50 (median):     {p50:.1f}ms")
                print(f"  P95:              {p95:.1f}ms")
                print(f"  P99:              {p99:.1f}ms")

    print("=" * 70)

    return 0 if failed_queries == 0 else 1

if __name__ == "__main__":
    if len(sys.argv) < 5:
        print("Usage: python3 test-mssql-realistic.py <server> <database> <username> <password> [port] [duration_minutes] [min_interval] [max_interval] [pool_size]")
        print()
        print("Arguments:")
        print("  server          - Database server IP/hostname")
        print("  database        - Database name")
        print("  username        - Database username")
        print("  password        - Database password")
        print("  port            - Database port (default: 1433)")
        print("  duration_minutes- Test duration in minutes (default: 10)")
        print("  min_interval    - Minimum seconds between queries (default: 1.0)")
        print("  max_interval    - Maximum seconds between queries (default: 5.0)")
        print("  pool_size       - Number of connections in pool (default: 10)")
        print()
        print("Example:")
        print("  python3 test-mssql-realistic.py 172.16.4.207 master sa MyPass123")
        print("  python3 test-mssql-realistic.py 172.16.4.207 master sa MyPass123 1433")
        print("  python3 test-mssql-realistic.py 172.16.4.207 master sa MyPass123 1433 15 0.5 3.0 20")
        print()
        print("This simulates real application behavior:")
        print("  - Connection pooling (reuses connections)")
        print("  - Random query intervals (realistic load pattern)")
        print("  - Multiple concurrent workers")
        print("  - Continuous monitoring and statistics")
        sys.exit(1)

    server = sys.argv[1]
    database = sys.argv[2]
    username = sys.argv[3]
    password = sys.argv[4]
    port = int(sys.argv[5]) if len(sys.argv) > 5 else 1433
    duration_minutes = int(sys.argv[6]) if len(sys.argv) > 6 else 10
    min_interval = float(sys.argv[7]) if len(sys.argv) > 7 else 1.0
    max_interval = float(sys.argv[8]) if len(sys.argv) > 8 else 5.0
    pool_size = int(sys.argv[9]) if len(sys.argv) > 9 else 10

    sys.exit(test_realistic_workload(server, database, username, password, port,
                                     duration_minutes, min_interval, max_interval, pool_size))
