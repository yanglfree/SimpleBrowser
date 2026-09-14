#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import time


HOST = "127.0.0.1"
PORT = 8776
TOTAL_BYTES = 100 * 1024 * 1024
CHUNK_SIZE = 64 * 1024
FIXTURE = Path(__file__).with_name("download.html")


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/download.html":
            body = FIXTURE.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if self.path == "/tiny.txt":
            body = b"ZhuoBrowser download fixture\n"
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Disposition", 'attachment; filename="tiny.txt"')
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if self.path == "/slow.bin":
            self.serve_slow_download()
            return
        self.send_error(404)

    def serve_slow_download(self):
        start = 0
        range_header = self.headers.get("Range", "")
        if range_header.startswith("bytes="):
            start_text = range_header.removeprefix("bytes=").split("-", 1)[0]
            if start_text.isdigit():
                start = min(int(start_text), TOTAL_BYTES - 1)
        self.send_response(206 if start else 200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Disposition", 'attachment; filename="resumable-fixture.bin"')
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(TOTAL_BYTES - start))
        if start:
            self.send_header("Content-Range", f"bytes {start}-{TOTAL_BYTES - 1}/{TOTAL_BYTES}")
        self.end_headers()
        remaining = TOTAL_BYTES - start
        chunk = b"Z" * CHUNK_SIZE
        try:
            while remaining > 0:
                part = chunk[:min(CHUNK_SIZE, remaining)]
                self.wfile.write(part)
                self.wfile.flush()
                remaining -= len(part)
                time.sleep(0.05)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def log_message(self, format, *args):
        print(format % args, flush=True)


if __name__ == "__main__":
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
