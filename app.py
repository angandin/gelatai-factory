"""
Flask app to serve the pygbag-built game as a web application.
Suitable for Azure Web App deployment and local testing.
"""
from flask import Flask, send_from_directory
import os

app = Flask(__name__, static_folder="build/web", static_url_path="")


@app.route("/")
def index():
    return send_from_directory(app.static_folder, "index.html")


@app.route("/<path:path>")
def static_files(path):
    return send_from_directory(app.static_folder, path)


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8000))
    app.run(host="0.0.0.0", port=port, debug=True)
