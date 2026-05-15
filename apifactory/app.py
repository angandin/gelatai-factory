"""
API Factory - Machine Simulator REST API.

Exposes endpoints to start/stop machine simulators and update machine configuration.
Each machine defined in the JSON config sends payloads to Event Hub while running.
"""
import os
import json
import threading
import time
from flask import Flask, jsonify, request

app = Flask(__name__)

# --- Simulator State ---
_lock = threading.Lock()
_running = False
_machines: list[dict] = []
_machine_threads: dict[str, threading.Thread] = {}
_stop_event = threading.Event()


def _send_to_event_hub(machine: dict):
    """Send a payload to Event Hub for a given machine.
    Called periodically while the simulator is running.
    Payload format TBD.
    """
    # TODO: define payload structure and Event Hub connection
    payload = {
        "machine_id": machine["id"],
        "timestamp": time.time(),
    }
    print(f"[EventHub] Would send: {json.dumps(payload)}")


def _machine_loop(machine: dict, stop_event: threading.Event):
    """Background loop for a single machine. Sends payloads at the configured interval."""
    interval = machine.get("interval_seconds", 5)
    while not stop_event.is_set():
        _send_to_event_hub(machine)
        stop_event.wait(interval)


def _start_machines():
    """Start background threads for all configured machines."""
    global _machine_threads, _stop_event
    _stop_event.clear()
    for machine in _machines:
        mid = machine["id"]
        t = threading.Thread(target=_machine_loop, args=(machine, _stop_event), daemon=True)
        _machine_threads[mid] = t
        t.start()


def _stop_machines():
    """Signal all machine threads to stop and wait for them."""
    global _machine_threads
    _stop_event.set()
    for t in _machine_threads.values():
        t.join(timeout=10)
    _machine_threads.clear()


# --- REST API ---

@app.route("/health")
def health():
    return jsonify({"status": "ok"})


@app.route("/simulator/start", methods=["POST"])
def start_simulator():
    """Start all machine simulators."""
    global _running
    with _lock:
        if _running:
            return jsonify({"error": "Simulator already running"}), 409
        if not _machines:
            return jsonify({"error": "No machines configured. POST /simulator/config first"}), 400
        _running = True
        _start_machines()
    return jsonify({"status": "started", "machines": len(_machines)})


@app.route("/simulator/stop", methods=["POST"])
def stop_simulator():
    """Stop all machine simulators."""
    global _running
    with _lock:
        if not _running:
            return jsonify({"error": "Simulator not running"}), 409
        _stop_machines()
        _running = False
    return jsonify({"status": "stopped"})


@app.route("/simulator/config", methods=["POST"])
def update_config():
    """Push a new machine configuration JSON.
    If the simulator is running, it will be restarted with the new config.

    Expected body: { "machines": [ { "id": "...", "interval_seconds": 5, ... }, ... ] }
    """
    global _machines, _running
    data = request.get_json(force=True)
    if "machines" not in data or not isinstance(data["machines"], list):
        return jsonify({"error": "Body must contain a 'machines' array"}), 400

    with _lock:
        was_running = _running
        if was_running:
            _stop_machines()
            _running = False

        _machines = data["machines"]

        if was_running:
            _start_machines()
            _running = True

    return jsonify({
        "status": "config_updated",
        "machines": len(_machines),
        "restarted": was_running,
    })


@app.route("/simulator/status", methods=["GET"])
def simulator_status():
    """Get current simulator status."""
    return jsonify({
        "running": _running,
        "machines_configured": len(_machines),
        "active_threads": len(_machine_threads),
    })


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    app.run(host="0.0.0.0", port=port, debug=True)
