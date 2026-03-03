from flask import Flask, request, jsonify
import requests
import os

app = Flask(__name__)

VERSION = os.environ.get("VERSION", "v1")
DOWNSTREAM_URL = os.environ.get("DOWNSTREAM_URL", "http://downstream-v1:8080")
APP_NAME = os.environ.get("APP_NAME", "backend")


@app.route("/health")
def health():
    return jsonify({"status": "healthy", "version": VERSION, "app": APP_NAME})


@app.route("/", defaults={"path": ""})
@app.route("/<path:path>")
def handle(path):
    # Forward all incoming headers to downstream
    headers_to_forward = {
        k: v for k, v in request.headers if k.lower() not in ("host", "content-length")
    }
    headers_to_forward["X-Forwarded-Via"] = f"{APP_NAME}-{VERSION}"

    downstream_url = f"{DOWNSTREAM_URL}/{path}" if path else DOWNSTREAM_URL
    try:
        resp = requests.get(
            downstream_url,
            headers=headers_to_forward,
            params=request.args,
            timeout=5,
        )
        downstream_data = resp.json()
    except Exception as e:
        downstream_data = {"error": str(e), "downstream_url": downstream_url}

    return jsonify(
        {
            "app": APP_NAME,
            "version": VERSION,
            "downstream_url": DOWNSTREAM_URL,
            "received_headers": dict(request.headers),
            "downstream": downstream_data,
        }
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
