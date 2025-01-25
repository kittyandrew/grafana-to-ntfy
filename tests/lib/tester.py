#!/usr/bin/env python
from pathlib import Path
import websocket
import requests
import json
import sys
import os


ntfy_url = os.environ["NTFY_URL"]
meta_info = Path("/tmp/metadata.txt").read_text().strip("\n\r\t ")


def on_message(_, message):
    msg = json.loads(message)
    if msg["event"] == "open":
        print(f"[{meta_info}] Ntfy.sh websocket connected success: {msg}", file=sys.stderr)
        # Grafana is provisioned and configured to send alerts after some "minimal" period of
        # time. However for prometheus we simulate that behavior by creating alert via an API.
        # This sucks, but I could not make it work otherwise (properly configure prometheus).
        #
        # In practice this somewhat hinders prometheus testing, but actually works much faster
        # because "minimal" period of time to first alert in grafana is very long (at least,
        # as far as my attempts at configuring it went). On my machine, as of Jan 25 2025,
        # Prometheus tests run in 25s vs 78s for Grafana.
        if "prometheus" in meta_info:
            payload, url = [{"labels": {"alertname": "myalert"}}], os.environ["ALERTMANAGER_URL"]
            requests.post(f"http://{url}/api/v2/alerts", json=payload)
    elif msg["event"] == "message":
        print(f"[{meta_info}] Ntfy.sh websocket message success: {msg}", file=sys.stderr)
        wsapp.keep_running = False
    else:
        print(f"[{meta_info}] Error (unexpected event): {msg}", file=sys.stderr)
        exit(666)


if __name__ == "__main__":
    wsapp = websocket.WebSocketApp(f"ws://{ntfy_url}/ws", on_message=on_message, on_error=lambda _, e: exit(666))
    wsapp.run_forever()
