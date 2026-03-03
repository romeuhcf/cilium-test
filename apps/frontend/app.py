from flask import Flask, request, jsonify, render_template_string
import requests
import os

app = Flask(__name__)

BACKEND_URL = os.environ.get("BACKEND_URL", "http://backend:8080")
VERSION = os.environ.get("VERSION", "v1")

HTML = """<!DOCTYPE html>
<html>
<head>
  <title>Cilium Service Mesh Demo</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 0; background: #1a1a2e; color: #eee; }
    .header { background: #16213e; padding: 20px 40px; border-bottom: 2px solid #0f3460; }
    .header h1 { margin: 0; color: #e94560; }
    .header p { margin: 5px 0 0; color: #aaa; font-size: 14px; }
    .container { max-width: 1100px; margin: 30px auto; padding: 0 20px; }
    .card { background: #16213e; padding: 25px; border-radius: 10px; margin: 15px 0; border: 1px solid #0f3460; }
    .card h2 { margin-top: 0; color: #e94560; font-size: 18px; }
    .flow { display: flex; align-items: center; gap: 12px; flex-wrap: wrap; margin: 15px 0; }
    .node { background: #0f3460; color: white; padding: 12px 20px; border-radius: 8px; text-align: center; min-width: 100px; }
    .node .label { font-size: 11px; color: #aaa; }
    .node .name { font-weight: bold; }
    .arrow { font-size: 22px; color: #e94560; }
    .btn { background: #e94560; color: white; border: none; padding: 10px 22px; border-radius: 6px; cursor: pointer; margin: 5px; font-size: 14px; }
    .btn:hover { background: #c73652; }
    .btn-secondary { background: #0f3460; }
    .btn-secondary:hover { background: #1a4a80; }
    pre { background: #0a0a1a; padding: 15px; border-radius: 6px; overflow-x: auto; font-size: 12px; color: #7fff7f; border: 1px solid #0f3460; max-height: 400px; overflow-y: auto; }
    .link { color: #e94560; }
    .badge { display: inline-block; padding: 3px 10px; border-radius: 12px; font-size: 12px; font-weight: bold; }
    .badge-v1 { background: #2d7a2d; color: white; }
    .badge-v2 { background: #7a5c2d; color: white; }
    .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 15px; }
    .info-row { display: flex; gap: 10px; align-items: center; margin: 5px 0; font-size: 13px; }
    .info-label { color: #aaa; min-width: 120px; }
    .spinner { display: none; color: #e94560; margin-left: 10px; }
    #error { color: #e94560; padding: 10px; display: none; }
  </style>
</head>
<body>
  <div class="header">
    <h1>Cilium Service Mesh Demo</h1>
    <p>eBPF-powered traffic management &amp; observability</p>
  </div>
  <div class="container">
    <div class="card">
      <h2>Traffic Flow</h2>
      <div class="flow">
        <div class="node"><div class="label">you</div><div class="name">Browser</div></div>
        <div class="arrow">→</div>
        <div class="node"><div class="label">frontend</div><div class="name">Frontend</div></div>
        <div class="arrow">→</div>
        <div class="node"><div class="label">active version</div><div class="name" id="backend-node">Backend</div></div>
        <div class="arrow">→</div>
        <div class="node"><div class="label">matching version</div><div class="name" id="downstream-node">Downstream</div></div>
      </div>
      <p style="font-size:13px; color:#aaa; margin:10px 0 0">
        Cilium CiliumNetworkPolicy ensures backend-v1 can only reach downstream-v1, and backend-v2 can only reach downstream-v2.
        Use the switch scripts to change which backend version is active.
      </p>
    </div>

    <div class="card">
      <h2>Send Request</h2>
      <button class="btn" onclick="makeRequest()">Single Request</button>
      <button class="btn btn-secondary" onclick="generateTraffic()">Generate Traffic (20x)</button>
      <span class="spinner" id="spinner">⏳ Loading...</span>
      <div id="error"></div>
      <div id="response" style="margin-top:15px;"></div>
    </div>

    <div class="card">
      <h2>Observe with Hubble</h2>
      <div class="info-row"><span class="info-label">Hubble UI:</span><a href="http://localhost:8888" target="_blank" class="link">http://localhost:8888</a></div>
      <div class="info-row"><span class="info-label">Namespace:</span><span>demo</span></div>
      <p style="font-size:13px; color:#aaa;">In Hubble UI, select the <strong>demo</strong> namespace to see traffic flowing between frontend → backend → downstream.</p>
    </div>
  </div>

  <script>
    async function makeRequest() {
      const spinner = document.getElementById('spinner');
      const err = document.getElementById('error');
      spinner.style.display = 'inline';
      err.style.display = 'none';
      try {
        const resp = await fetch('/api/call', {
          headers: {
            'X-Request-Source': 'frontend-ui',
            'X-Demo-Header': 'cilium-mesh',
            'X-Trace-Id': 'trace-' + Math.random().toString(36).substr(2,9)
          }
        });
        const data = await resp.json();
        updateNodes(data);
        document.getElementById('response').innerHTML = '<pre>' + JSON.stringify(data, null, 2) + '</pre>';
      } catch(e) {
        err.textContent = 'Error: ' + e;
        err.style.display = 'block';
      } finally {
        spinner.style.display = 'none';
      }
    }

    async function generateTraffic() {
      const spinner = document.getElementById('spinner');
      spinner.style.display = 'inline';
      spinner.textContent = '⏳ Generating traffic...';
      let last;
      for (let i = 0; i < 20; i++) {
        try {
          const resp = await fetch('/api/call', {
            headers: {
              'X-Request-Source': 'traffic-generator',
              'X-Request-Num': String(i+1)
            }
          });
          last = await resp.json();
        } catch(e) {}
        await new Promise(r => setTimeout(r, 200));
      }
      spinner.style.display = 'none';
      spinner.textContent = '⏳ Loading...';
      if (last) {
        updateNodes(last);
        document.getElementById('response').innerHTML = '<pre>Last response (20 requests sent):\n' + JSON.stringify(last, null, 2) + '</pre>';
      }
    }

    function updateNodes(data) {
      const bk = data.backend_response;
      if (bk && bk.version) {
        document.getElementById('backend-node').textContent = 'Backend ' + bk.version;
      }
      if (bk && bk.downstream && bk.downstream.version) {
        document.getElementById('downstream-node').textContent = 'Downstream ' + bk.downstream.version;
      }
    }
  </script>
</body>
</html>
"""


@app.route("/")
def index():
    return render_template_string(HTML)


@app.route("/api/call")
def api_call():
    headers_to_forward = {
        k: v for k, v in request.headers if k.lower() not in ("host", "content-length")
    }
    headers_to_forward["X-Forwarded-From"] = "frontend"

    try:
        resp = requests.get(BACKEND_URL, headers=headers_to_forward, timeout=5)
        backend_data = resp.json()
    except Exception as e:
        backend_data = {"error": str(e)}

    return jsonify({"frontend_version": VERSION, "backend_response": backend_data})


@app.route("/health")
def health():
    return jsonify({"status": "healthy", "version": VERSION, "app": "frontend"})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
