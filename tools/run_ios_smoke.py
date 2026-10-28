"""Run the real wardrobe smoke test from a clean, non-iCloud build directory.

The maintained checkout can live in Documents, whose Finder metadata prevents
Apple signing generated frameworks. Copy only build inputs without extended
attributes; retain the isolated directory for inspecting native build failures.
Local demo Auth and tools/run_wardrobe_dev.py must already be running.
"""
import argparse
import hashlib
from pathlib import Path
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--device', required=True, help='Booted iOS simulator identifier')
parser.add_argument('--flutter', default='/opt/homebrew/bin/flutter')
args = parser.parse_args()
source = Path(__file__).resolve().parents[1]
target = Path(tempfile.mkdtemp(prefix='vyoora-ios-smoke-', dir='/private/tmp'))
ignore = shutil.ignore_patterns('Pods', '.symlinks', 'ephemeral', 'xcuserdata', '.DS_Store',
                                '*.backup', 'Generated.xcconfig', 'flutter_export_environment.sh',
                                'GeneratedPluginRegistrant.*', '.last_build_id')
for name in ('lib', 'assets', 'ios', 'integration_test'):
    shutil.copytree(source/name, target/name, ignore=ignore, copy_function=shutil.copy)
for name in ('pubspec.yaml', 'pubspec.lock'):
    shutil.copy(source/name, target/name)
for name in ('lib', 'integration_test'):
    for file in (source/name).rglob('*.dart'):
        copied = target/file.relative_to(source)
        assert hashlib.sha256(file.read_bytes()).digest() == hashlib.sha256(copied.read_bytes()).digest()
print(f'Exact source copied without Finder metadata to {target}', flush=True)
result = subprocess.run([args.flutter, 'test', 'integration_test/wardrobe_smoke_test.dart',
    '-d', args.device, '--dart-define=FIREBASE_PROJECT_ID=demo-vyoora-v2',
    '--dart-define=AUTH_EMULATOR_HOST=127.0.0.1:9099',
    '--dart-define=WARDROBE_API_BASE_URL=http://127.0.0.1:7359'], cwd=target)
raise SystemExit(result.returncode)
