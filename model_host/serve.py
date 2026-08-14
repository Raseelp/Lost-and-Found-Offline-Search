#!/usr/bin/env python3
"""
Local dev server for testing the model download flow. Serves the .pt files
in this directory with HTTP Range support, which Python's stock http.server
doesn't have (and ModelManager's resume logic needs it).

Usage: python serve.py [port]   (default 8000)
"""
import http.server
import os
import re
import socketserver
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
DIRECTORY = os.path.dirname(os.path.abspath(__file__))


class _LimitedReader:
    """Wraps a file object so copyfile() only ever reads `remaining` bytes."""

    def __init__(self, f, remaining):
        self._f = f
        self._remaining = remaining

    def read(self, size=-1):
        if self._remaining <= 0:
            return b""
        if size < 0 or size > self._remaining:
            size = self._remaining
        chunk = self._f.read(size)
        self._remaining -= len(chunk)
        return chunk

    def close(self):
        self._f.close()


class RangeRequestHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

    def send_head(self):
        path = self.translate_path(self.path)
        if not os.path.isfile(path):
            return super().send_head()

        file_size = os.path.getsize(path)
        range_header = self.headers.get("Range")

        if range_header is None:
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Length", str(file_size))
            self.send_header("Accept-Ranges", "bytes")
            self.end_headers()
            return open(path, "rb")

        match = re.match(r"bytes=(\d+)-(\d*)", range_header)
        if not match:
            self.send_response(416)
            self.end_headers()
            return None

        start = int(match.group(1))
        end = int(match.group(2)) if match.group(2) else file_size - 1
        end = min(end, file_size - 1)

        if start >= file_size:
            self.send_response(416)
            self.send_header("Content-Range", f"bytes */{file_size}")
            self.end_headers()
            return None

        length = end - start + 1

        self.send_response(206)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(length))
        self.send_header("Content-Range", f"bytes {start}-{end}/{file_size}")
        self.send_header("Accept-Ranges", "bytes")
        self.end_headers()

        f = open(path, "rb")
        f.seek(start)
        return _LimitedReader(f, length)


class ThreadingHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True


if __name__ == "__main__":
    server = ThreadingHTTPServer(("0.0.0.0", PORT), RangeRequestHandler)
    print(f"Serving {DIRECTORY} at http://0.0.0.0:{PORT}")
    print(f"  Emulator:        http://10.0.2.2:{PORT}")
    print(f"  Physical device: http://<this-machine-LAN-IP>:{PORT}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
