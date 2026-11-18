#!/usr/bin/env python3
"""Package only the self-contained public architecture document for static hosting."""
import argparse
import base64
from hashlib import sha256
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parent.parent


class Links(HTMLParser):
    def handle_starttag(self, tag, attrs):
        for key, value in attrs:
            if key == 'href' and value and re.search(r'(?i)^(?:file:|https?://(?:localhost|127\.0\.0\.1))', value):
                raise ValueError('Public HTML contains a local-file link.')


def package(output):
    output.mkdir(parents=True, exist_ok=True)
    html = (ROOT / 'docs/architecture/index.html').read_text()
    Links().feed(html)
    if re.search(r'<a\b[^>]*href=["\'][^"\']*(?:127\.0\.0\.1|localhost|file:)', html, re.I):
        raise ValueError('Embedded source-link template contains a loopback/file URL.')
    api_html = (ROOT / 'docs/api/index.html').read_text()
    Links().feed(api_html)
    scripts = re.findall(r'<script(?![^>]*type="application/json")[^>]*>(.*?)</script>', html + api_html, re.S)
    hashes = ['sha256-' + base64.b64encode(sha256(script.encode()).digest()).decode() for script in scripts]
    csp = "default-src 'none'; script-src " + ' '.join("'"+h+"'" for h in hashes) + "; style-src 'unsafe-inline'; font-src data:; img-src data:; connect-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'"
    (output / 'index.html').write_text(html)
    (output / 'api').mkdir(exist_ok=True)
    (output / 'api/index.html').write_text(api_html)
    (output / 'api/openapi.yaml').write_bytes((ROOT / 'docs/api/openapi.yaml').read_bytes())
    (output / 'api/schema.graphql').write_bytes((ROOT / 'contracts/schema.graphql').read_bytes())
    (output / '404.html').write_text('<!doctype html><html lang="en"><meta charset="utf-8"><title>Page not found</title><h1>Page not found</h1><a href="/">Open the architecture walkthrough</a></html>')
    (output / 'robots.txt').write_text('User-agent: *\nDisallow: /\n')
    (output / '_headers').write_text('/*\n  Cache-Control: public, max-age=0, must-revalidate, no-transform\n  X-Content-Type-Options: nosniff\n  Referrer-Policy: strict-origin-when-cross-origin\n  X-Robots-Tag: noindex\n  Content-Security-Policy: '+csp+'\n')
    commit = subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
    data = json.loads(re.search(r'<script id="architecture-data" type="application/json">(.*?)</script>',html,re.S).group(1))
    metadata = {'document_commit':commit,'engine_source_commit':data['source_commit'],'html_sha256':sha256(html.encode()).hexdigest(),'api_html_sha256':sha256(api_html.encode()).hexdigest(),'openapi_sha256':sha256((output/'api/openapi.yaml').read_bytes()).hexdigest(),'static_only':True,'authentication_required':False}
    (output / 'build-metadata.json').write_text(json.dumps(metadata,indent=2)+'\n')
    expected={'index.html','404.html','robots.txt','_headers','build-metadata.json','api/index.html','api/openapi.yaml','api/schema.graphql'}
    if {p.relative_to(output).as_posix() for p in output.rglob('*') if p.is_file()} != expected:
        raise ValueError('Unexpected file in static publication directory.')
    print(json.dumps({'files':sorted(expected),'html_bytes':len(html.encode()),**metadata}))


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=ROOT/'.runtime/publication/site')
    package(parser.parse_args().output)
