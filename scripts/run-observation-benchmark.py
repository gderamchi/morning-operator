#!/usr/bin/env python3
import argparse
import json
import os
from pathlib import Path
import plistlib
import selectors
import signal
import re
import subprocess
import time

parser = argparse.ArgumentParser(description='Record a booted iOS simulator while XCTest drives two separately installed synthetic fixture apps. Local artifacts only; no model scoring is implied.')
parser.add_argument('--variant', choices=['baseline', 'heldout'], default='baseline')
parser.add_argument('--device', required=True, help='UUID of a booted iOS simulator')
parser.add_argument('--run', required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
device = args.device
if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_-]{0,63}', args.run):
    parser.error('--run must be a short filename-safe run identifier')
devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', '--json'], text=True))
if not any(item['udid'] == device and item['state'] == 'Booted' and item.get('isAvailable')
           for runtime, items in devices['devices'].items() if '.iOS-' in runtime for item in items):
    parser.error('--device must identify an available, booted iOS simulator')
products = root / '.build/benchmark/Build/Products'
out = root / 'work/observation-benchmark' / args.run
out.mkdir(parents=True, exist_ok=False)
candidates = list(products.glob('MorningObservationBenchmark_*.xctestrun'))
if len(candidates) != 1:
    parser.error('Build MorningObservationBenchmark into .build/benchmark first; expected one generated xctestrun')
original = candidates[0]
with original.open('rb') as f:
    configuration = plistlib.load(f)
target = configuration['MorningObservationBenchmarkUITests']
target.setdefault('EnvironmentVariables', {}).update({
    'MO_OBSERVATION_BENCHMARK': '1',
    'MO_OBSERVATION_BENCHMARK_VARIANT': args.variant,
})
configured = products / f'Observation-{args.run}.xctestrun'
with configured.open('wb') as f:
    plistlib.dump(configuration, f)
for app in ('MorningBenchmarkInbox', 'MorningBenchmarkCalendar'):
    subprocess.run(['xcrun', 'simctl', 'install', device,
                    str(products / 'Debug-iphonesimulator' / (app + '.app'))], check=True)

def stamp():
    return {'monotonicSeconds': time.monotonic(), 'unixSeconds': time.time()}

metadata = {'variant': args.variant, 'origin': 'synthetic', 'recordCommandBefore': stamp(),
            'alignment': 'Recording-start notification bounds first frame; controller truth is scored separately, never model input.'}
movie = out / 'recording.mov'
recorder = subprocess.Popen(['xcrun', 'simctl', 'io', device, 'recordVideo', '--codec=h264', str(movie)],
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
metadata['recordCommandAfter'] = stamp()
selector = selectors.DefaultSelector()
selector.register(recorder.stdout, selectors.EVENT_READ)
log = bytearray()
test = None
try:
    deadline = time.monotonic() + 30
    while b'Recording started' not in log:
        if time.monotonic() >= deadline or recorder.poll() is not None:
            raise RuntimeError('Simulator recording never reported its first frame.')
        for key, _ in selector.select(0.25):
            data = os.read(key.fileobj.fileno(), 4096)
            if data:
                log.extend(data)
    metadata['recordingStartedObserved'] = stamp()
    print('Real simulator recording started; running the independent action sequence.', flush=True)
    with (out / 'xcode-test.log').open('wb') as output:
        metadata['testCommandBefore'] = stamp()
        test = subprocess.Popen(['xcodebuild', 'test-without-building', '-xctestrun', str(configured),
            '-destination', f'platform=iOS Simulator,id={device}', '-parallel-testing-enabled', 'NO',
            '-collect-test-diagnostics', 'never', '-resultBundlePath', str(out / 'test.xcresult')],
            cwd=root, stdout=output, stderr=subprocess.STDOUT)
        metadata['testExitCode'] = test.wait(timeout=900)
        metadata['testCommandAfter'] = stamp()
finally:
    if test is not None and test.poll() is None:
        test.terminate()
        test.wait(timeout=30)
    metadata['recordingStopRequested'] = stamp()
    if recorder.poll() is None:
        recorder.send_signal(signal.SIGINT)
    selector.close()
    remaining, _ = recorder.communicate(timeout=60)
    log.extend(remaining)
    metadata['recordingExitCode'] = recorder.returncode
    metadata['recordingFinalizedObserved'] = stamp()
    (out / 'recorder.log').write_bytes(log)
    (out / 'capture-metadata.json').write_text(json.dumps(metadata, indent=2))
print(json.dumps({'output': str(out), 'testExit': metadata.get('testExitCode'),
                  'recordingExit': recorder.returncode, 'movieBytes': movie.stat().st_size}, indent=2), flush=True)
raise SystemExit(metadata.get('testExitCode', 1))
