#!/usr/bin/env python3
"""Loopback-only read-only architecture preview with allowlisted source viewing."""
import argparse
from hashlib import sha256
from html import escape
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
from urllib.parse import unquote, urlsplit, parse_qs

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / 'docs/architecture'


class Handler(BaseHTTPRequestHandler):
    def send(self, status, data, content_type='text/html; charset=utf-8'):
        if isinstance(data, str):
            data = data.encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'no-store')
        if urlsplit(self.path).path == '/download':
            self.send_header('Content-Disposition', 'attachment; filename="savvy-billing-architecture.html"')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Referrer-Policy', 'no-referrer')
        self.send_header('Content-Security-Policy', "default-src 'self' data:; script-src 'unsafe-inline'; style-src 'unsafe-inline'; font-src data:; img-src data:; object-src 'none'; base-uri 'none'; frame-ancestors 'none'")
        self.end_headers()
        if self.command != 'HEAD':
            self.wfile.write(data)

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        if self.headers.get('Host') not in {f'127.0.0.1:{self.server.server_port}', f'localhost:{self.server.server_port}'}:
            self.send(403, 'Host not allowed.', 'text/plain; charset=utf-8')
            return
        url = urlsplit(self.path)
        path = unquote(url.path)
        if path in {'/', '/index.html', '/architecture.html', '/download'}:
            self.send(200, (DOCS / 'index.html').read_bytes())
            return
        api_files = {'/api/': (ROOT/'docs/api/index.html', 'text/html; charset=utf-8'), '/api/index.html': (ROOT/'docs/api/index.html', 'text/html; charset=utf-8'), '/api/openapi.yaml': (ROOT/'docs/api/openapi.yaml', 'application/yaml; charset=utf-8'), '/api/schema.graphql': (ROOT/'contracts/schema.graphql', 'text/plain; charset=utf-8')}
        if path in api_files:
            target, content_type = api_files[path]
            self.send(200, target.read_bytes(), content_type)
            return
        if path == '/health':
            self.send(200, json.dumps({'status': 'ok', 'read_only': True}), 'application/json')
            return
        if not path.startswith('/source/'):
            self.send(404, 'Not found.', 'text/plain; charset=utf-8')
            return
        name = path[len('/source/'):]
        allowed = set(json.loads((DOCS / 'source-map.json').read_text())['paths'])
        target = (ROOT / name).resolve()
        if name not in allowed or not target.is_relative_to(ROOT) or not target.is_file():
            self.send(404, 'Source not found.', 'text/plain; charset=utf-8')
            return
        body = target.read_text()
        if parse_qs(url.query).get('raw') == ['1']:
            self.send(200, body, 'text/plain; charset=utf-8')
            return
        digest = sha256(target.read_bytes()).hexdigest()
        lines = '\n'.join(f'<div class="line" id="L{i}"><a href="#L{i}" aria-label="Line {i}">{i}</a><code>{escape(line) or " "}</code></div>' for i, line in enumerate(body.splitlines(), 1))
        self.send(200, f'''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>{escape(name)} | Savvy source</title>
<style>body{{margin:0;background:#fcfbf9;color:#08261e;font:14px/1.6 system-ui,sans-serif}}header{{padding:24px 30px;border-bottom:1px solid #d3cdc4;overflow-wrap:anywhere}}h1{{font-size:20px;font-weight:500}}a{{color:#175242}}small{{color:#60675f}}main{{padding:20px 0;overflow:auto}}.line{{display:grid;grid-template-columns:70px 1fr;min-width:max-content;padding-right:25px;scroll-margin-top:20px}}.line:target{{background:#e8ddaa}}.line a{{color:#8e7e57;text-align:right;padding-right:22px;text-decoration:none;user-select:none}}code{{font:13px/1.65 ui-monospace,monospace;white-space:pre}}a:focus-visible{{outline:2px solid #8e7e57}}@media(max-width:600px){{header{{padding:18px}}.line{{grid-template-columns:50px 1fr}}}}</style>
<header><a href="/">← Architecture walkthrough</a><h1>{escape(name)}</h1><p>Current local checkout · read-only source viewer</p><small>SHA-256: {digest}</small> · <a href="?raw=1">Plain text</a></header><main>{lines}</main></html>''')

    def log_message(self, fmt, *args):
        print(fmt % args, flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=3105)
    args = parser.parse_args()
    if not (DOCS / 'index.html').is_file():
        parser.error('Build docs/architecture/index.html first.')
    server = ThreadingHTTPServer(('127.0.0.1', args.port), Handler)
    print(f'Architecture preview: http://127.0.0.1:{args.port}/', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
