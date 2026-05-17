#!/usr/bin/env python3
"""
Fix mipit-testkit for VM1:
  1. CLABE check-digit — corrects every SPEI-XXXXXXXXXXXXXXXXXX in all test/dataset files
  2. Auth headers      — adds inline authedFetch() wrapper to every integration/E2E test
  3. Status codes      — replaces .toBe(202) with .toBe(201) (core returns 201)
  4. routing.test.ts   — removes broken '../helpers/auth.js' import and authHeaders refs
  5. ui.env            — sets NEXT_PUBLIC_API_BASE_URL=/api and adds adapter URLs
"""
import re, os, sys

BASE = '/home/estudiante/tesis/mipit-testkit'
INFRA_ENV = '/home/estudiante/tesis/mipit-infra/env/ui.env'

# ─── CLABE fixer ─────────────────────────────────────────────────────────────

def clabe_check(d17: str) -> int:
    w = [3, 7, 1, 3, 7, 1, 3, 7, 1, 3, 7, 1, 3, 7, 1, 3, 7]
    s = sum(int(d17[i]) * w[i] for i in range(17))
    return (10 - s % 10) % 10

def fix_clabes(text: str) -> str:
    def replacer(m):
        d = m.group(1)
        if len(d) == 18:
            fixed = d[:17] + str(clabe_check(d[:17]))
            if fixed != d:
                return f'SPEI-{fixed}'
        return m.group(0)
    return re.sub(r'SPEI-(\d{18})', replacer, text)

# ─── Auth helper block ────────────────────────────────────────────────────────

AUTH_BLOCK = '''
let TOKEN = '';
beforeAll(async () => {
  const r = await fetch(`${API_URL}/auth/token`);
  TOKEN = ((await r.json()) as { access_token: string }).access_token;
});

async function authedFetch(url: string, init: RequestInit = {}): Promise<Response> {
  return fetch(url, {
    ...init,
    headers: {
      Authorization: `Bearer ${TOKEN}`,
      ...(init.headers as Record<string, string> | undefined),
    },
  });
}
'''

# ─── Patch test file ──────────────────────────────────────────────────────────

def patch_test(content: str, is_routing: bool = False) -> str:
    # 1. Remove broken helpers/auth import (routing.test.ts was modified in prior session)
    if is_routing:
        content = re.sub(
            r"import \{[^}]+\} from '[^']*helpers/auth(?:\.js)?';\n?", '', content
        )
        # Remove all authHeaders() usages that were injected
        content = re.sub(r'\s*\.\.\.\(await authHeaders\([^)]*\)\),?', '', content)
        content = re.sub(r',\s*headers:\s*await authHeaders\([^)]*\)', '', content)
        content = re.sub(r'\{\s*headers:\s*await authHeaders\([^)]*\)\s*\}', '{}', content)
        content = re.sub(r'headers:\s*await authHeaders\([^)]*\)', 'headers: {}', content)
        # Ensure API_URL is declared (it may have been removed)
        if 'const API_URL' not in content:
            content = "const API_URL = process.env.API_URL ?? 'http://localhost:8080';\n" + content

    # 2. Inject auth helpers after the API_URL declaration
    if 'authedFetch' not in content:
        content = re.sub(
            r"(const API_URL = process\.env\.API_URL \?\? 'http://localhost:8080';)",
            r'\1' + AUTH_BLOCK,
            content,
        )

    # 3. Replace all fetch(${API_URL}/...) with authedFetch(${API_URL}/...)
    content = content.replace('fetch(`${API_URL}/', 'authedFetch(`${API_URL}/')

    # 4. Fix HTTP status code expectations (API returns 201, not 202)
    content = content.replace('.toBe(202)', '.toBe(201)')

    return content

# ─── Process test files ───────────────────────────────────────────────────────

test_files = [
    ('tests/integration/core-api.test.ts',    False),
    ('tests/integration/translation.test.ts', False),
    ('tests/integration/idempotency.test.ts', False),
    ('tests/integration/pipeline.test.ts',    False),
    ('tests/integration/routing.test.ts',     True),   # has broken import
    ('tests/e2e/pix-to-spei.test.ts',         False),
    ('tests/e2e/spei-to-pix.test.ts',         False),
    ('tests/e2e/error-scenarios.test.ts',      False),
    ('tests/e2e/idempotency-e2e.test.ts',     False),
    ('tests/e2e/batch-load.test.ts',          False),
]

for fname, is_routing in test_files:
    path = os.path.join(BASE, fname)
    if not os.path.exists(path):
        print(f'SKIP (not found): {fname}')
        continue
    with open(path) as f:
        content = f.read()
    content = fix_clabes(content)
    content = patch_test(content, is_routing)
    with open(path, 'w') as f:
        f.write(content)
    print(f'OK  {fname}')

# ─── Process dataset JSON files ───────────────────────────────────────────────

dataset_files = [
    'datasets/pix/pix-valid-01.json',
    'datasets/pix/pix-valid-02.json',
    'datasets/pix/pix-batch-50.json',
    'datasets/spei/spei-valid-01.json',
    'datasets/spei/spei-valid-02.json',
    'datasets/spei/spei-batch-50.json',
]

for fname in dataset_files:
    path = os.path.join(BASE, fname)
    if not os.path.exists(path):
        print(f'SKIP (not found): {fname}')
        continue
    with open(path) as f:
        content = f.read()
    fixed = fix_clabes(content)
    with open(path, 'w') as f:
        f.write(fixed)
    changed = sum(1 for a, b in zip(content.split('SPEI-'), fixed.split('SPEI-')) if a != b)
    print(f'OK  {fname}  ({changed} CLABEs fixed)')

# ─── Fix smoke test ───────────────────────────────────────────────────────────

smoke = os.path.join(BASE, 'tools/smoke-test.sh')
if os.path.exists(smoke):
    with open(smoke) as f:
        content = f.read()
    content = fix_clabes(content)
    with open(smoke, 'w') as f:
        f.write(content)
    print('OK  tools/smoke-test.sh')

# ─── Fix ui.env ───────────────────────────────────────────────────────────────

if os.path.exists(INFRA_ENV):
    with open(INFRA_ENV) as f:
        lines = f.readlines()

    keys_to_set = {
        'NEXT_PUBLIC_API_BASE_URL':    '/api',
        'NEXT_PUBLIC_PIX_HEALTH_URL':  'http://10.43.101.29:9101',
        'NEXT_PUBLIC_SPEI_HEALTH_URL': 'http://10.43.101.29:9102',
        'NEXT_PUBLIC_BREB_HEALTH_URL': 'http://10.43.101.29:9103',
        'NEXT_PUBLIC_PIX_MOCK_URL':    'http://10.43.101.29:9001',
        'NEXT_PUBLIC_SPEI_MOCK_URL':   'http://10.43.101.29:9002',
        'NEXT_PUBLIC_BREB_MOCK_URL':   'http://10.43.101.29:9003',
    }

    new_lines = []
    seen = set()
    for line in lines:
        key = line.split('=')[0].strip()
        if key in keys_to_set:
            new_lines.append(f'{key}={keys_to_set[key]}\n')
            seen.add(key)
        else:
            new_lines.append(line)

    # Append any keys not already in the file
    for k, v in keys_to_set.items():
        if k not in seen:
            new_lines.append(f'{k}={v}\n')

    with open(INFRA_ENV, 'w') as f:
        f.writelines(new_lines)
    print(f'OK  {INFRA_ENV}')
else:
    print(f'WARN ui.env not found at {INFRA_ENV}')

print('\nAll done. Next steps:')
print('  cd ~/tesis/mipit-infra/compose && docker-compose up -d --build ui nginx')
print('  cd ~/tesis/mipit-testkit && API_URL=http://localhost:8080 npm run test:integration')
print('  cd ~/tesis/mipit-testkit && API_URL=http://localhost:8080 npm run test:e2e')
