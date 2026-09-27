#!/usr/bin/env python3
"""Two controlled SOCKS5 nodes for OpenWrt proxy-group smoke tests.

The nodes answer HTTP requests for 198.51.100.123:18100 with their node letter.
GET /health returns 204; GET /trace returns A or B. With --speed-cert and --speed-key, HTTPS speed samples use a test certificate
trusted only by the disposable VM. /A/slow and /A/fast control throughput;
/state reports speed-check counts. Without a certificate, speed samples fail.
"""

import argparse
import base64
import json
import socketserver
import ssl
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


TARGET = "198.51.100.123"
TARGET_PORT = 18100
state = {"A": True, "B": True}
speeds = {"A": "fast", "B": "fast"}
checks = {"A": 0, "B": 0}
subscription_reversed = False
lock = threading.Lock()


def receive_exact(conn, count):
    data = b""
    while len(data) < count:
        part = conn.recv(count - len(data))
        if not part:
            raise ConnectionError("peer closed")
        data += part
    return data


class SocksHandler(socketserver.BaseRequestHandler):
    def handle(self):
        conn = self.request
        conn.settimeout(5)
        try:
            head = receive_exact(conn, 2)
            if head[0] != 5:
                return
            receive_exact(conn, head[1])
            conn.sendall(b"\x05\x00")
            head = receive_exact(conn, 4)
            if head[:3] != b"\x05\x01\x00":
                return
            if head[3] == 1:
                address = ".".join(str(x) for x in receive_exact(conn, 4))
            elif head[3] == 3:
                address = receive_exact(conn, receive_exact(conn, 1)[0]).decode()
            elif head[3] == 4:
                receive_exact(conn, 16)
                return
            else:
                return
            port = int.from_bytes(receive_exact(conn, 2), "big")
            with lock:
                available = state[self.server.node]
            is_speed = port == 443 and getattr(self.server, "speed_tls", None) is not None
            if not available or (not is_speed and (address != TARGET or port != TARGET_PORT)):
                conn.sendall(b"\x05\x05\x00\x01\x00\x00\x00\x00\x00\x00")
                return
            conn.sendall(b"\x05\x00\x00\x01\x00\x00\x00\x00\x00\x00")
            if is_speed:
                conn = self.server.speed_tls.wrap_socket(conn, server_side=True)
            request = b""
            while b"\r\n\r\n" not in request and len(request) < 8192:
                request += conn.recv(1024)
            path = request.split(b" ", 2)[1] if b" " in request else b""
            if is_speed:
                with lock:
                    speed = speeds[self.server.node]
                    checks[self.server.node] += 1
                body = b"x" * 262144
                conn.sendall(b"HTTP/1.1 200 OK\r\nContent-Length: 262144\r\nConnection: close\r\n\r\n")
                for i in range(0, len(body), 8192):
                    if speed == "slow": time.sleep(0.125)
                    conn.sendall(body[i:i+8192])
                conn.close()
            elif path == b"/health":
                if self.server.node == "B":
                    time.sleep(0.5)
                conn.sendall(b"HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n")
            elif path == b"/trace":
                body = self.server.node.encode()
                conn.sendall(b"HTTP/1.1 200 OK\r\nContent-Length: 1\r\nConnection: close\r\n\r\n" + body)
            else:
                conn.sendall(b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
        except (ConnectionError, IndexError, OSError, TimeoutError):
            return


class SocksServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


class ControlHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/subscription":
            with lock:
                names = ("B", "A") if subscription_reversed else ("A", "B")
            lines = [
                f"socks5://10.0.2.2:{18101 if name == 'A' else 18102}#sub{name}"
                for name in names
            ]
            body = base64.b64encode(("\n".join(lines) + "\n").encode())
            self.send_response(200)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if self.path != "/state":
            self.send_error(404)
            return
        with lock:
            body = json.dumps({"available": state, "speeds": speeds, "checks": checks}).encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        global subscription_reversed
        parts = self.path.strip("/").split("/")
        if parts == ["subscription", "reverse"]:
            with lock:
                subscription_reversed = not subscription_reversed
            self.send_response(204)
            self.end_headers()
            return
        if len(parts) == 2 and parts[0] in speeds and parts[1] in ("slow", "fast"):
            with lock: speeds[parts[0]] = parts[1]
            self.send_response(204)
            self.end_headers()
            return
        if len(parts) != 2 or parts[0] not in state or parts[1] not in ("up", "down"):
            self.send_error(404)
            return
        with lock:
            state[parts[0]] = parts[1] == "up"
        self.send_response(204)
        self.end_headers()

    def log_message(self, *_):
        pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--first-port", type=int, default=18101)
    parser.add_argument("--second-port", type=int, default=18102)
    parser.add_argument("--control-port", type=int, default=18103)
    parser.add_argument("--speed-cert")
    parser.add_argument("--speed-key")
    args = parser.parse_args()
    tls = None
    if args.speed_cert:
        tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        tls.load_cert_chain(args.speed_cert, args.speed_key)
    servers = []
    for node, port in (("A", args.first_port), ("B", args.second_port)):
        server = SocksServer((args.host, port), SocksHandler)
        server.node = node
        server.speed_tls = tls
        servers.append(server)
    servers.append(ThreadingHTTPServer((args.host, args.control_port), ControlHandler))
    for server in servers:
        threading.Thread(target=server.serve_forever, daemon=True).start()
    print("Local SOCKS fixtures A/B and control endpoint ready", flush=True)
    threading.Event().wait()


if __name__ == "__main__":
    main()
