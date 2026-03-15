#!/usr/bin/env python
from pathlib import Path
import threading
import websocket
import json
import sys
import os


TIMEOUT_SECONDS = 120

ntfy_url = os.environ["NTFY_URL"]
meta_info = Path("/tmp/metadata.txt").read_text().strip("\n\r\t ")


if __name__ == "__main__":
    def on_message(_, message):
        msg = json.loads(message)
        if msg["event"] == "open":
            print(f"[{meta_info}] Ntfy.sh websocket connected success: {msg}", file=sys.stderr)
        elif msg["event"] == "message":
            print(f"[{meta_info}] Ntfy.sh websocket message success: {msg}", file=sys.stderr)
            # @NOTE: Validate notification content to catch silent regressions in
            #  status mapping, priority extraction, or title handling.
            assert msg.get("title"), f"Expected non-empty title, got: {msg.get('title')}"
            tags = msg.get("tags", [])
            assert "warning" in tags, f"Expected 'warning' emoji tag, got: {tags}"
            assert "firing" in tags, f"Expected 'firing' status tag, got: {tags}"
            if "prometheus" in meta_info:
                assert msg["title"] == "Alertmanager", f"Expected title 'Alertmanager', got: {msg['title']}"
            wsapp.keep_running = False
        elif msg["event"] == "keepalive":
            pass  # @NOTE: ntfy sends keepalive events every ~45s — ignore them.
        else:
            print(f"[{meta_info}] Error (unexpected event): {msg}", file=sys.stderr)
            sys.stderr.flush()
            os._exit(1)

    def on_timeout():
        print(f"[{meta_info}] Error: timed out after {TIMEOUT_SECONDS}s waiting for notification", file=sys.stderr)
        sys.stderr.flush()
        wsapp.keep_running = False
        os._exit(1)

    def on_error(_, e):
        print(f"[{meta_info}] WebSocket error: {e}", file=sys.stderr)
        sys.stderr.flush()
        os._exit(1)

    wsapp = websocket.WebSocketApp(f"ws://{ntfy_url}/ws", on_message=on_message, on_error=on_error)
    timer = threading.Timer(TIMEOUT_SECONDS, on_timeout)
    timer.daemon = True
    timer.start()
    wsapp.run_forever()
    timer.cancel()
