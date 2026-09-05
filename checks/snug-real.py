#!/usr/bin/env python3
"""Real Nix lifecycle using tiny local packages; never changes the caller's profile."""
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'packages/snug'))
import snug

with tempfile.TemporaryDirectory(prefix='snug-real-') as temp:
    root = Path(temp)
    os.environ['HOME'] = str(root / 'home')
    os.environ['XDG_STATE_HOME'] = str(root / 'state')
    os.environ['XDG_DATA_HOME'] = str(root / 'data')
    Path(os.environ['HOME']).mkdir()
    fixture = root / 'fixture'
    fixture.mkdir()
    builder = os.environ['SNUG_TEST_BASH']
    def version(value):
        expression = '''{ outputs = { self }: {
          packages.x86_64-linux.nested.widget = builtins.derivation {
            name = "snug-widget-%s";
            system = "x86_64-linux";
            builder = %s;
            args = [ "-c" "mkdir -p $out/bin; echo '#!%s' > $out/bin/widget; echo 'echo %s' >> $out/bin/widget; chmod +x $out/bin/widget" ];
            PATH = %s;
          };
        }; }''' % (value, json.dumps(builder), builder, value, json.dumps(os.environ['SNUG_TEST_PATH']))
        (fixture / 'flake.nix').write_text(expression)
    snug.SOURCE = 'path:' + str(fixture)
    version('one')
    snug.main(['-i', 'nested.widget'])
    profile = Path(os.environ['XDG_STATE_HOME']) / 'snug/profile'
    assert (profile / 'bin/widget').is_file()
    result = snug.run([str(profile / 'bin/widget')], capture_output=True, text=True)
    assert result.stdout.strip() == 'one'
    snug.main(['-it', 'nested.widget', '--', 'widget'])
    before = profile.resolve()
    version('two')
    snug.main(['-u'])
    assert profile.resolve() != before
    result = snug.run([str(profile / 'bin/widget')], capture_output=True, text=True)
    assert result.stdout.strip() == 'two'
    snug.main(['-b'])
    assert profile.resolve() == before
    snug.main(['-r', 'nested.widget'])
    assert not (profile / 'bin/widget').exists()
    assert not (Path(os.environ['HOME']) / '.nix-profile').exists()
    print('Real Nix install / temporary shell / update / rollback / remove: PASS')
