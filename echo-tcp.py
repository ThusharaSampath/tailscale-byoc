import socket
import threading

HOST = '0.0.0.0'
PORT = 8070

def handle_client(conn, addr):
    """Handle a single client connection in a separate thread"""
    with conn:
        print(f'Connected by {addr}')
        try:
            while True:
                data = conn.recv(1024)
                if not data:
                    print(f'Connection closed by {addr}')
                    break
                print(f'Received from {addr}: {data.decode("utf-8", errors="ignore").strip()}')
                conn.sendall(data)
        except Exception as e:
            print(f'Error handling {addr}: {e}')
        finally:
            print(f'Thread for {addr} finished')

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind((HOST, PORT))
    s.listen()
    print(f'Multi-threaded echo server listening on {HOST}:{PORT}')

    while True:
        conn, addr = s.accept()
        # Create a new thread for each client connection
        client_thread = threading.Thread(target=handle_client, args=(conn, addr), daemon=True)
        client_thread.start()
        print(f'Started thread for {addr}')