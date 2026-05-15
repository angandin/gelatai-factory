"""
Flask app to serve the pygbag-built game as a web application.
Suitable for Azure Web App deployment and local testing.
"""
from flask import Flask, send_from_directory, make_response
import os

app = Flask(__name__, static_folder="game/build/web", static_url_path="")


@app.after_request
def add_headers(response):
    # Use credentialless to allow loading cross-origin CDN resources (pygbag WASM runtime)
    response.headers["Cross-Origin-Opener-Policy"] = "same-origin"
    response.headers["Cross-Origin-Embedder-Policy"] = "credentialless"
    # Cache control for development
    response.headers["Cache-Control"] = "no-cache"
    return response


@app.route("/")
def index():
    return send_from_directory(app.static_folder, "index.html")


@app.route("/<path:path>")
def static_files(path):
    # Ensure correct MIME types for pygbag assets
    mimetype = None
    if path.endswith(".apk"):
        mimetype = "application/zip"
    elif path.endswith(".tar.gz"):
        mimetype = "application/gzip"
    elif path.endswith(".wasm"):
        mimetype = "application/wasm"
    elif path.endswith(".js"):
        mimetype = "application/javascript"
    elif path.endswith(".mjs"):
        mimetype = "application/javascript"

    if mimetype:
        return send_from_directory(app.static_folder, path, mimetype=mimetype)
    return send_from_directory(app.static_folder, path)


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8000))
    app.run(host="0.0.0.0", port=port, debug=True)
