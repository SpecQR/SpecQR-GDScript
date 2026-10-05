"""Development-only differential checks against the audited Perl reference.

This file is not required by or imported from the native GDScript runtime.
Provide the Perl source root and Godot executable explicitly.
"""
import argparse, json, math, os, pathlib, random, subprocess, tempfile, sys
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / 'script'))
from native_support import strict_json
from prepare_ci import inventory

def require(value, message):
    if not value:
        raise RuntimeError(message)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--perl-root', required=True)
    ap.add_argument('--godot', required=True)
    args = ap.parse_args()
    source = pathlib.Path(__file__).resolve().parents[1]
    initial = inventory(source)
    randomizer = random.Random(60644)
    requests = []
    for n in range(120):
        alphabet = randomizer.choice(['0123456789', 'ABC123 $%*+-./:', 'a1b23C45DEF67é', '漢字123ABCaé😀', '%ABC%123%%'])
        text = ''.join((randomizer.choice(alphabet) for _ in range(randomizer.randrange(0, 320))))
        opts = {'errorCorrectionLevel': randomizer.choice('LMQH'), 'allowKanji': bool(randomizer.randrange(2)), 'optimizeSegments': bool(randomizer.randrange(2)), 'minVersion': randomizer.choice([1, 9, 10, 26, 27])}
        if n % 5 == 0:
            opts['fnc1'] = True
        if n % 7 == 0:
            opts['eci'] = 26
        if n % 11 == 0:
            opts['boostErrorCorrection'] = True
        requests.append({'command': 'plan', 'text': text, 'options': opts})
    for text in ['ABC%DEF', '%%%%%%%%%%', 'A%1234567890%BB', 'AB' + chr(29) + 'CD', '漢字ABC123', '', 'aé😀%']:
        for opts in [{'fnc1': True}, {'fnc1Second': 'A'}, {'eci': 26}, {'mode': 'byte'}]:
            requests.append({'command': 'generate', 'text': text, 'options': {**opts, 'maskPattern': 3}, 'diagnostics': True})
    for text in ['ABC123'.__mul__(20), '0123456789'.__mul__(20), 'é漢字😀abc%'.__mul__(10), 'hello world '.__mul__(10)]:
        for opts in [{'version': 1, 'errorCorrectionLevel': 'L'}, {'version': 2, 'optimizeSegments': False}, {'minVersion': 1, 'maxVersion': 4, 'allowKanji': False}]:
            requests.append({'command': 'structured-append', 'text': text, 'options': {**opts, 'maskPattern': 0}, 'diagnostics': True})
    for segments in [[{'mode': 'numeric', 'text': '12345'}, {'mode': 'byte', 'text': 'aé😀'.__mul__(20)}, {'mode': 'alphanumeric', 'text': 'END'}], [{'mode': 'byte', 'bytes': list(range(128))}], [{'mode': 'numeric', 'text': '12345'.__mul__(30)}], [{'mode': 'kanji', 'text': '漢字'}] * 12]:
        requests.append({'command': 'structured-append', 'segments': segments, 'options': {'version': 2, 'maskPattern': 2}, 'diagnostics': True})
    payload = ''.join((json.dumps(r, ensure_ascii=True, separators=(',', ':')) + '\n' for r in requests))
    ref = subprocess.run(['perl', str(pathlib.Path(args.perl_root) / 'script/bridge.pl')], input=payload, text=True, capture_output=True, timeout=120)
    with tempfile.TemporaryDirectory(prefix='specqr-api-sa-') as home:
        env = {**os.environ, 'HOME': home, 'XDG_DATA_HOME': home + '/data', 'XDG_CACHE_HOME': home + '/cache', 'XDG_CONFIG_HOME': home + '/config'}
        for folder in ['data', 'cache', 'config']:
            pathlib.Path(home, folder).mkdir()
        actual = subprocess.run([args.godot, '--headless', '--no-header', '--path', str(source), '--script', 'res://script/bridge.gd'], input=payload, text=True, capture_output=True, env=env, timeout=120)
    for name, result in [('reference', ref), ('native', actual)]:
        require(result.returncode == 0, (name, result.returncode, result.stderr))
        require(result.stderr == '', (name, result.stderr))
    expected_rows = [strict_json(line) for line in ref.stdout.splitlines()]
    actual_rows = [strict_json(line) for line in actual.stdout.splitlines()]
    require(len(expected_rows) == len(actual_rows) == len(requests), (len(expected_rows), len(actual_rows), len(requests)))

    def compare(expected, actual, path=''):
        if isinstance(expected, dict) and expected.get('isSpecQRError'):
            require(isinstance(actual, dict) and actual.get('isSpecQRError') and (actual.get('code') == expected['code']), (path, expected, actual))
        elif isinstance(expected, dict):
            require(isinstance(actual, dict) and expected.keys() == actual.keys(), (path, expected.keys(), actual))
            for k, v in expected.items():
                compare(v, actual[k], path + '/' + k)
        elif isinstance(expected, list):
            require(isinstance(actual, list) and len(expected) == len(actual), (path, len(expected), actual))
            for i, (x, y) in enumerate(zip(expected, actual)):
                compare(x, y, path + '/' + str(i))
        elif isinstance(expected, (int, float)) and (not isinstance(expected, bool)):
            require(not isinstance(actual, bool) and isinstance(actual, (int, float)) and math.isclose(expected, actual, rel_tol=1e-12, abs_tol=1e-12), (path, expected, actual))
        else:
            require(expected == actual and type(expected) is type(actual), (path, expected, actual))
    for i, (expected, actual) in enumerate(zip(expected_rows, actual_rows)):
        try:
            compare(expected, actual)
        except AssertionError as exc:
            raise AssertionError({'index': i, 'request': requests[i], 'difference': exc.args}) from exc
    require(inventory(source) == initial, 'Source changed during optional oracle')
    print(json.dumps({'status': 'passed', 'requests': len(requests), 'godot': args.godot, 'seed': 60644}))
if __name__ == '__main__':
    main()
