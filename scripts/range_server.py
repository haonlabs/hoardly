#!/usr/bin/env python3
"""Static file server with HTTP Range support, for testing Hoardly.

usage: range_server.py DIR [--port 8765] [--no-range] [--rate BYTES_PER_SEC] [--drop BYTES] [--max-conns N] [--cookie-log FILE]
  --rate  throttle each connection
  --drop  cut every connection after this many bytes (exercises retry/resume)
  --max-conns  answer 429 + Retry-After beyond N concurrent transfers (like proof.ovh.net)
  --cookie-log append '<path> <Cookie header>' for every request
"""
import argparse, mimetypes, os, re, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


active = 0
lock = threading.Lock()


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        global active
        with lock:
            if args.max_conns and active >= args.max_conns:
                self.send_response(429)
                self.send_header('Retry-After', '2')
                self.send_header('Content-Length', '0')
                return self.end_headers()
            active += 1
        try:
            self.serve()
        finally:
            with lock:
                active -= 1

    def serve(self):
        if args.cookie_log:
            with open(args.cookie_log, 'a') as log:
                log.write(f"{self.path} {self.headers.get('Cookie', '')}\n")
        path = os.path.join(args.dir, os.path.basename(self.path.split('?')[0]))
        if not os.path.isfile(path):
            return self.send_error(404)
        size = os.path.getsize(path)
        start, end = 0, size - 1
        match = re.fullmatch(r'bytes=(\d+)-(\d*)', self.headers.get('Range', ''))
        if match and not args.no_range:
            start, end = int(match[1]), min(int(match[2] or size - 1), size - 1)
            if start >= size:
                return self.send_error(416)
            self.send_response(206)
            self.send_header('Content-Range', f'bytes {start}-{end}/{size}')
        else:
            self.send_response(200)
        self.send_header('Content-Length', str(end - start + 1))
        self.send_header('Content-Type', mimetypes.guess_type(path)[0] or 'application/octet-stream')
        self.send_header('ETag', f'"{int(os.path.getmtime(path))}-{size}"')
        self.end_headers()
        sent = 0
        with open(path, 'rb') as f:
            f.seek(start)
            left = end - start + 1
            while left > 0:
                chunk = f.read(min(65536, left))
                try:
                    self.wfile.write(chunk)
                except (BrokenPipeError, ConnectionResetError):
                    return
                left -= len(chunk)
                sent += len(chunk)
                if args.drop and sent >= args.drop:
                    return  # short body: client sees a dropped connection
                if args.rate:
                    time.sleep(len(chunk) / args.rate)

    def log_message(self, *_):
        pass


parser = argparse.ArgumentParser()
parser.add_argument('dir')
parser.add_argument('--port', type=int, default=8765)
parser.add_argument('--no-range', action='store_true')
parser.add_argument('--rate', type=float, default=0)
parser.add_argument('--drop', type=int, default=0)
parser.add_argument('--max-conns', type=int, default=0)
parser.add_argument('--cookie-log')
args = parser.parse_args()
ThreadingHTTPServer(('127.0.0.1', args.port), Handler).serve_forever()
