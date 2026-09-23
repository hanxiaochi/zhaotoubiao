"""Run on the owner's server. Never commit the resulting .env."""
from pathlib import Path
import getpass
import secrets

target = Path(__file__).resolve().parent / '.env'
if target.exists():
    raise SystemExit('Existing .env preserved; edit deliberately, do not regenerate secrets.')
key = getpass.getpass('MiniMax API Key (hidden; server-only): ').strip()
if not key or any(character in key for character in '\r\n\x00\'"$# '):
    raise SystemExit('Missing or unsupported key format')
values = {
    'APP_HOST': '212.64.108.243', 'APP_HOSTS': '212.64.108.243,localhost,127.0.0.1',
    'BIND_ADDRESS': '0.0.0.0', 'HTTP_PORT': '9052',
    'DB_PASSWORD': secrets.token_hex(24), 'SECRET_KEY_BASE': secrets.token_hex(64),
    'STORAGE_USER': 'donghua' + secrets.token_hex(6), 'STORAGE_PASSWORD': secrets.token_hex(32),
    'OCR_WORKER_TOKEN': secrets.token_hex(32), 'AI_PROVIDER': 'minimax',
    'AI_BASE_URL': 'https://api.minimax.cn/v1', 'AI_MODEL': 'MiniMax-M3', 'AI_API_KEY': key,
}
import os
descriptor = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(descriptor, 'w', encoding='utf-8', newline='\n') as output:
    output.write(''.join(f'{name}={value}\n' for name, value in values.items()))
print('Private server configuration generated; key not displayed.')
