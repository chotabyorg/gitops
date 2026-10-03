"""Pilot readiness: authenticated local workers/state, no provider requests."""
import json
import os
from pathlib import Path
import urllib.request

try:
    request = urllib.request.Request(
        'http://127.0.0.1:8080/api/status',
        headers={'Authorization': 'Bearer ' + os.environ['API_TOKEN']},
    )
    with urllib.request.urlopen(request, timeout=3) as response:
        status = json.load(response)
    expected = {'transcription', 'outbound', 'maintenance'}
    if set(status['workers']) != expected or any(
        item['state'] != 'running' for item in status['workers'].values()
    ):
        raise RuntimeError('workers unavailable')
    if any(status['configuration'][name] for name in (
        'outbound_enabled', 'ami_enabled', 'final_transcription_enabled', 'transcription_key_present'
    )):
        raise RuntimeError('inert configuration changed')
    # Check PVC writability without touching business tables or recording metadata.
    with __import__('tempfile').TemporaryFile(dir='/app/data') as stream:
        stream.write(b'voice-readiness')
        stream.flush()
except Exception:
    # Do not print requests, credentials, provider config or exception detail.
    raise SystemExit(1)
