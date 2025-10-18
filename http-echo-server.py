from http.server import HTTPServer, BaseHTTPRequestHandler
import json
from datetime import datetime

HOST = '0.0.0.0'
PORT = 8070

class EchoHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_echo_response()

    def do_POST(self):
        self.send_echo_response()

    def do_PUT(self):
        self.send_echo_response()

    def do_DELETE(self):
        self.send_echo_response()

    def send_echo_response(self):
        # Read request body
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length).decode('utf-8') if content_length > 0 else ''

        # Build response
        response_data = {
            'timestamp': datetime.now().isoformat(),
            'method': self.command,
            'path': self.path,
            'headers': dict(self.headers),
            'body': body,
            'client': f"{self.client_address[0]}:{self.client_address[1]}"
        }

        response_json = json.dumps(response_data, indent=2)

        # Send HTTP response
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', len(response_json))
        self.end_headers()
        self.wfile.write(response_json.encode())

        # Log to console
        print(f"[{datetime.now().strftime('%H:%M:%S')}] {self.command} {self.path} from {self.client_address[0]}")
        if body:
            print(f"  Body: {body[:100]}{'...' if len(body) > 100 else ''}")

if __name__ == '__main__':
    server = HTTPServer((HOST, PORT), EchoHandler)
    print(f"HTTP Echo Server running on {HOST}:{PORT}")
    print(f"Test with: curl http://localhost:{PORT}/test")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down server...")
        server.shutdown()
