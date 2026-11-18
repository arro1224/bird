"""Loopback-only HTTP control for the existing real timeout/recovery test.

Run: python test/support/serve_disconnect_reproduction.py --port 8766
Then set BIRDBOX_DISCONNECT_FIXTURE=http://127.0.0.1:8766 before running
test/bird_companion/features/connection/business_http_disconnect_reproduction_test.dart.
No phone, real box, credentials, or user photos are used.
"""
import argparse
import json
import time
import uuid
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        started = time.monotonic()
        try:
            request_id = str(uuid.UUID(self.headers.get('X-Request-Id', '')))
        except ValueError:
            request_id = str(uuid.uuid4())
        route = self.path.split('?', 1)[0]
        delays = {
            '/api/v1/smart-follow-sessions/slow': 16.5,
            '/api/v1/smart-follow-sessions/field-status-delay': 6.2,
        }
        time.sleep(delays.get(route, 0))
        status = 503 if route == '/api/v1/smart-follow-sessions/http-503' else 200
        body = json.dumps({'data': {'healthy': True, 'items': []}}).encode()
        delivered = False
        try:
            self.send_response(status)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.send_header('X-Request-Id', request_id)
            self.end_headers()
            self.wfile.write(body)
            delivered = True
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            pass
        print(json.dumps({
            'event': 'api_request', 'request_id': request_id,
            'route': route if route in delays or route in {'/health', '/api/v1/device/status', '/api/v1/projects', '/api/v1/smart-follow-sessions/http-503'} else '/{unknown}',
            'status': status, 'elapsed_ms': round((time.monotonic() - started) * 1000),
            'write_returned': delivered,
            'finished_at': datetime.now(timezone.utc).isoformat(),
        }), flush=True)

    def log_message(self, *_args):
        pass


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=8766)
    args = parser.parse_args()
    server = ThreadingHTTPServer(('127.0.0.1', args.port), Handler)
    print(f'BIRDBOX_DISCONNECT_FIXTURE=http://127.0.0.1:{server.server_port}', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
