#!/usr/bin/env python3
"""Stateful loopback Screenote API fixture for the CLI snapshot smoke."""

import hashlib
import json
import os
import pathlib
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


PORT_FILE = pathlib.Path(sys.argv[1])
REPORT_FILE = pathlib.Path(sys.argv[2])
STATE = {
    "prepare_calls": 0,
    "prepare_identity": None,
    "prepare_identical": True,
    "uploads": {},
}


def digest(namespace, components):
    hasher = hashlib.sha256()
    hasher.update(namespace.encode())
    hasher.update(b"\0")
    for component in components:
        encoded = str(component).encode()
        hasher.update(str(len(encoded)).encode())
        hasher.update(b":")
        hasher.update(encoded)
    return hasher.hexdigest()


def response_for(request, resumed):
    groups = {}
    for entry in request["entries"]:
        groups.setdefault((entry["page"], entry["title"]), []).append(entry)
    group_digests = {}
    for key, entries in groups.items():
        components = [key[0], key[1], len(entries)]
        for entry in entries:
            components.extend(
                [
                    entry["viewport"],
                    entry["mime_type"],
                    entry["content_sha256"],
                    entry["file_ref_sha256"],
                ]
            )
        group_digests[key] = digest("screenote-screenshot-v1", components)
    entries = []
    for index, entry in enumerate(request["entries"]):
        entries.append(
            {
                "screenshot_id": 200 + index,
                "manifest_entry_digest": group_digests[(entry["page"], entry["title"])],
                "page_id": 300 + index,
                "page": entry["page"],
                "title": entry["title"],
                "image_id": 100 + index,
                "viewport": entry["viewport"],
                "mime_type": entry["mime_type"],
                "content_sha256": entry["content_sha256"],
                "state": "processing" if resumed and index == 0 else "awaiting_upload",
                "status": "pending",
                "attached": bool(resumed and index == 0),
            }
        )
    return {
        "operation": "resumed" if resumed else "created",
        "snapshot_id": 41,
        "project_id": 7,
        "manifest_digest": request["manifest_digest"],
        "git_commit": request["git_commit"],
        "taken_at": request["taken_at"],
        "state": "awaiting_upload",
        "review_url": "",
        "entries": entries,
    }


def write_report():
    temporary = REPORT_FILE.with_suffix(".tmp")
    temporary.write_text(json.dumps(STATE, sort_keys=True))
    os.replace(temporary, REPORT_FILE)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, _format, *_args):
        pass

    def send_json(self, status, payload):
        raw = json.dumps(payload, separators=(",", ":")).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_POST(self):
        if self.path != "/api/v1/projects/7/snapshots":
            self.send_json(404, {"code": "not_found", "error": "unexpected path"})
            return
        raw = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        request = json.loads(raw)
        identity = hashlib.sha256(raw).hexdigest()
        STATE["prepare_calls"] += 1
        if STATE["prepare_identity"] is None:
            STATE["prepare_identity"] = identity
        else:
            STATE["prepare_identical"] = (
                STATE["prepare_identical"] and identity == STATE["prepare_identity"]
            )
        resumed = STATE["prepare_calls"] > 1
        write_report()
        self.send_json(200, response_for(request, resumed))

    def do_PUT(self):
        prefix = "/api/v1/projects/7/screenshot_images/"
        if not self.path.startswith(prefix):
            self.send_json(404, {"code": "not_found", "error": "unexpected path"})
            return
        image_id = self.path.removeprefix(prefix)
        body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        STATE["uploads"][image_id] = STATE["uploads"].get(image_id, 0) + 1
        write_report()
        if image_id == "101" and STATE["uploads"][image_id] == 1:
            self.send_json(
                500, {"code": "upload_failed", "error": "forced resumable failure"}
            )
            return
        self.send_json(
            200,
            {
                "operation": "uploaded",
                "snapshot_id": 41,
                "screenshot_id": 100 + int(image_id),
                "image_id": int(image_id),
                "viewport": "desktop",
                "state": "processing",
                "status": "pending",
                "attached": bool(body),
                "snapshot_state": "awaiting_upload"
                if image_id == "100"
                else "processing",
            },
        )

    def do_GET(self):
        if self.path != "/api/v1/projects/7/snapshots/41":
            self.send_json(404, {"code": "not_found", "error": "unexpected path"})
            return
        self.send_json(
            200,
            {
                "operation": "status",
                "snapshot_id": 41,
                "project_id": 7,
                "state": "ready",
                "review_url": "http://127.0.0.1/reviews/41",
                "entries": [],
            },
        )


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
PORT_FILE.write_text(str(server.server_port))
write_report()
server.serve_forever()
