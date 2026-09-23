"""Read-only topology check with fake credentials. Does not start containers."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parent
with tempfile.TemporaryDirectory(prefix='donghua-compose-check-') as directory:
    fixture = Path(directory) / 'synthetic.env'
    fixture.write_text('DB_PASSWORD=synthetic\nSTORAGE_USER=synthetic\nSTORAGE_PASSWORD=synthetic\nOCR_WORKER_TOKEN=synthetic\n')
    environment = dict(os.environ, OWNER_ENV_FILE=str(fixture))
    result = subprocess.run(['docker', 'compose', '--env-file', str(fixture), '-f', str(root / 'compose.yml'),
                             'config', '--format', 'json'], env=environment, capture_output=True, text=True)
    if result.returncode:
        raise SystemExit('Compose parsing failed (diagnostics suppressed to avoid leaking local environment).')
    services = json.loads(result.stdout)['services']
    published = [(name, port['published']) for name, service in services.items() for port in service.get('ports', [])]
    assert published == [('proxy', '9052')], published
    assert services['web']['environment']['WEB_CONCURRENCY'] == '0'
    assert services['jobs']['environment']['JOB_THREADS'] == '1'
    assert services['ocr']['network_mode'] == 'service:web'
    assert services['jobs']['network_mode'] == 'service:web'
    assert services['web']['environment']['OCR_WORKER_URL'] == 'http://127.0.0.1:8100'
    steady = ['web', 'jobs', 'ocr', 'db', 'storage', 'proxy']
    memory = sum(int(services[name]['mem_limit']) for name in steady)
    assert memory == 3520 * 1024**2, memory
    print('PASS: only TCP 9052 published; bounded processes; loopback OCR; 3520 MiB steady-state memory ceilings. No services started.')
