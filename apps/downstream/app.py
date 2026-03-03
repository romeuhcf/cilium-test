from flask import Flask, request, jsonify
import os

app = Flask(__name__)

VERSION = os.environ.get("VERSION", "v1")
APP_NAME = os.environ.get("APP_NAME", "downstream")


@app.route("/health")
def health():
    return jsonify({"status": "healthy", "version": VERSION, "app": APP_NAME})


@app.route("/", defaults={"path": ""})
@app.route("/<path:path>")
def handle(path):
    return jsonify(
        {
            "app": APP_NAME,
            "version": VERSION,
            "path": f"/{path}" if path else "/",
            "received_headers": dict(request.headers),
        }
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
