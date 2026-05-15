"""
Web server to serve the pygbag-built game.
Uses http.server (matching pygbag's testserver) for local testing.
Also provides a Flask WSGI app for Azure Web App deployment via gunicorn.
"""
import os
import hashlib
import io
import urllib.request
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from http import HTTPStatus

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
STATIC_DIR = os.path.join(BASE_DIR, "game", "build", "web")
CACHE_DIR = os.path.join(BASE_DIR, "game", "build", "web-cache")
CDN_BASE = "https://pygame-web.github.io"

MIME_TYPES = {
    ".js": "application/javascript",
    ".mjs": "application/javascript",
    ".wasm": "application/wasm",
    ".data": "application/octet-stream",
    ".py": "application/octet-stream",
    ".whl": "application/zip",
    ".ogg": "audio/ogg",
    ".png": "image/png",
    ".html": "text/html",
    ".css": "text/css",
    ".gz": "application/gzip",
}


def get_mime_type(path):
    for ext, mime in MIME_TYPES.items():
        if path.endswith(ext):
            return mime
    return "application/octet-stream"


class GameHandler(SimpleHTTPRequestHandler):
    """HTTP handler matching pygbag's testserver behavior exactly."""

    def end_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cross-Origin-Resource-Policy", "cross-origin")
        self.send_header("Cross-Origin-Opener-Policy", "cross-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Origin-Agent-Cluster", "?1")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def do_GET(self):
        f = self.send_head()
        if f:
            try:
                self.copyfile(f, self.wfile)
            finally:
                f.close()

    def send_head(self):
        path = self.path.split("?")[0].split("#")[0]  # strip query/fragment

        # Serve index.html with CDN replacement
        if path == "/":
            return self._serve_index()

        # Serve CDN files from cache
        if path.startswith("/cdn/") or path.startswith("//cdn/"):
            cdn_path = path.lstrip("/")
            if cdn_path.startswith("cdn/"):
                cdn_path = cdn_path[4:]  # remove "cdn/"
            return self._serve_cdn(cdn_path)

        # Serve static files from build/web
        return self._serve_static(path.lstrip("/"))

    def _serve_index(self):
        index_path = os.path.join(STATIC_DIR, "index.html")
        if not os.path.isfile(index_path):
            self.send_error(HTTPStatus.NOT_FOUND)
            return None

        with open(index_path, "r", encoding="utf-8") as f:
            html = f.read()

        # Replace CDN base with local server (matching pygbag's behavior)
        host = self.headers.get("Host", f"localhost:{self.server.server_address[1]}")
        proxy = f"http://{host}"
        html = html.replace(CDN_BASE, proxy)

        # Disable service worker
        html = html.replace(
            f'navigator.serviceWorker.register("{proxy}/cdn/0.9.3/pygbag0.9.3.js")',
            'navigator.serviceWorker.getRegistrations().then(r=>r.forEach(sw=>sw.unregister()))')

        content = html.encode("utf-8")
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(content)))
        self.end_headers()
        return io.BytesIO(content)

    def _serve_cdn(self, cdn_path):
        full_url = f"{CDN_BASE}/cdn/{cdn_path}"
        cache_key = hashlib.md5(full_url.encode()).hexdigest()
        cache_file = os.path.join(CACHE_DIR, f"{cache_key}.data")

        if not os.path.isfile(cache_file):
            # Try to fetch from CDN
            try:
                req = urllib.request.Request(full_url, headers={"User-Agent": "Mozilla/5.0"})
                with urllib.request.urlopen(req, timeout=30) as resp:
                    data = resp.read()
                os.makedirs(CACHE_DIR, exist_ok=True)
                with open(cache_file, "wb") as f:
                    f.write(data)
            except Exception as e:
                self.send_error(HTTPStatus.NOT_FOUND, f"CDN fetch failed: {e}")
                return None

        with open(cache_file, "rb") as f:
            data = f.read()

        # Patch cpythonrc.py to use current origin for pkg_indexes (works for any host)
        if cdn_path.endswith("cpythonrc.py"):
            data = _patch_cpythonrc(data)

        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", get_mime_type(cdn_path))
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        return io.BytesIO(data)

    def _serve_static(self, rel_path):
        file_path = os.path.join(STATIC_DIR, rel_path.replace("/", os.sep))
        if not os.path.isfile(file_path):
            self.send_error(HTTPStatus.NOT_FOUND)
            return None

        with open(file_path, "rb") as f:
            data = f.read()

        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", get_mime_type(rel_path))
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        return io.BytesIO(data)

    def log_message(self, format, *args):
        """Log in a cleaner format."""
        import sys
        sys.stderr.write(f"{self.log_date_time_string()} {format % args}\n")
        sys.stderr.flush()


# Shared cpythonrc.py patch for any-origin pkg_indexes
_CPYTHONRC_OLD = """        # pygbag mode
        if platform.window.location.href.find("//localhost:") > 0:
            port = str(platform.window.location.port)

            # pygbag developer mode ( --dev )
            if ("-i" in PyConfig.orig_argv) or (port == "8666"):
                PyConfig.dev_mode = 1
                print(sys._emscripten_info)

            PyConfig.pygbag = 1
        else:
            PyConfig.pygbag = 0

        if (PyConfig.dev_mode > 0) or PyConfig.pygbag:
            # in pygbag dev mode use local repo
            PyConfig.pkg_indexes = []
            for idx in PYCONFIG_PKG_INDEXES_DEV:
                redirect = idx.replace("<port>", port)
                PyConfig.pkg_indexes.append(redirect)

            print("807: DEV MODE ON", PyConfig.pkg_indexes)"""

_CPYTHONRC_NEW = """        # Use current origin for package downloads (patched for self-hosted serving)
        PyConfig.pygbag = 1
        PyConfig.pkg_indexes = [str(platform.window.location.origin) + "/cdn/"]
        print("807: DEV MODE ON", PyConfig.pkg_indexes)"""


def _patch_cpythonrc(data):
    text = data.decode("utf-8")
    if _CPYTHONRC_OLD in text:
        text = text.replace(_CPYTHONRC_OLD, _CPYTHONRC_NEW)
        return text.encode("utf-8")
    return data


# === Flask WSGI app for Azure deployment (used by gunicorn) ===
from flask import Flask, Response as FlaskResponse, request as flask_request

flask_app = Flask(__name__, static_folder=None)


@flask_app.after_request
def add_headers(response):
    response.headers["Cache-Control"] = "no-store"
    response.headers["Access-Control-Allow-Origin"] = "*"
    response.headers["Cross-Origin-Resource-Policy"] = "cross-origin"
    response.headers["Cross-Origin-Opener-Policy"] = "cross-origin"
    response.headers["Cross-Origin-Embedder-Policy"] = "require-corp"
    response.headers["Connection"] = "close"
    return response


@flask_app.route("/")
def flask_index():
    index_path = os.path.join(STATIC_DIR, "index.html")
    with open(index_path, "r", encoding="utf-8") as f:
        html = f.read()
    scheme = flask_request.headers.get("X-Forwarded-Proto", flask_request.scheme)
    host = flask_request.headers.get("X-Forwarded-Host", flask_request.host)
    base_url = f"{scheme}://{host}"
    html = html.replace(CDN_BASE, base_url)
    html = html.replace(
        f'navigator.serviceWorker.register("{base_url}/cdn/0.9.3/pygbag0.9.3.js")',
        'navigator.serviceWorker.getRegistrations().then(r=>r.forEach(sw=>sw.unregister()))')
    return FlaskResponse(html, mimetype="text/html")


@flask_app.route("/cdn/<path:path>")
def flask_cdn(path):
    full_url = f"{CDN_BASE}/cdn/{path}"
    cache_key = hashlib.md5(full_url.encode()).hexdigest()
    cache_file = os.path.join(CACHE_DIR, f"{cache_key}.data")
    if os.path.isfile(cache_file):
        with open(cache_file, "rb") as f:
            data = f.read()
    else:
        try:
            req = urllib.request.Request(full_url, headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(req, timeout=30) as resp:
                data = resp.read()
            os.makedirs(CACHE_DIR, exist_ok=True)
            with open(cache_file, "wb") as f:
                f.write(data)
        except Exception as e:
            return FlaskResponse(f"CDN fetch failed: {e}", status=404)
    # Patch cpythonrc.py for any-origin pkg_indexes
    if path.endswith("cpythonrc.py"):
        data = _patch_cpythonrc(data)
    return FlaskResponse(data, mimetype=get_mime_type(path))


@flask_app.route("/<path:path>")
def flask_static(path):
    file_path = os.path.join(STATIC_DIR, path)
    if not os.path.isfile(file_path):
        return FlaskResponse("Not found", status=404)
    with open(file_path, "rb") as f:
        data = f.read()
    return FlaskResponse(data, mimetype=get_mime_type(path))


# For gunicorn: `gunicorn app:flask_app`
app = flask_app

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8000))
    print(f"Serving game on http://localhost:{port}/")
    handler = GameHandler
    handler.protocol_version = "HTTP/1.0"
    server = ThreadingHTTPServer(("0.0.0.0", port), handler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down.")
        server.shutdown()
