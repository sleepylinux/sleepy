"""Non-overwriting project environments backed by Nix flakes."""
from pathlib import Path
import os
import tempfile

from snug import NIX, SOURCE, SnugError, run

PRESETS = {'python': ['python3', 'uv'], 'node': ['nodejs'],
           'rust': ['rustc', 'cargo', 'rustfmt', 'clippy', 'pkg-config']}


def template(preset):
    packages = ' '.join(PRESETS[preset])
    return '''{
  description = "Snug development environment";
  inputs.nixpkgs.url = "''' + SOURCE + '''";
  outputs = { nixpkgs, ... }: let
    systems = [ "x86_64-linux" "aarch64-linux" ];
  in {
    devShells = nixpkgs.lib.genAttrs systems (system: let
      pkgs = import nixpkgs { inherit system; };
    in {
      default = pkgs.mkShell {
        packages = with pkgs; [ ''' + packages + ''' ];
      };
    });
  };
}
'''


def initialize(preset, target):
    if preset not in PRESETS:
        raise SnugError('Choose a preset: ' + ', '.join(PRESETS))
    target = Path(target).absolute()
    target.mkdir(parents=True, exist_ok=True)
    for name in ('flake.nix', 'flake.lock'):
        if os.path.lexists(target / name):
            raise SnugError(f'Refusing to overwrite {target / name}. Use snug -d to enter the existing project.')
    # Build the pair privately before publishing either file to the project.
    with tempfile.TemporaryDirectory(prefix='.snug-init-', dir=target) as temp:
        staging = Path(temp)
        (staging / 'flake.nix').write_text(template(preset))
        run(NIX + ['flake', 'lock', 'path:' + str(staging)], cwd=staging)
        created = []
        try:
            for name in ('flake.nix', 'flake.lock'):
                source = staging / name
                os.link(source, target / name)  # atomic no-replace, even during a concurrent init
                created.append((target / name, source.stat().st_ino))
        except BaseException:
            for path, inode in created:
                if path.lstat().st_ino == inode:
                    path.unlink()
            raise
    print(f'Created {preset} environment in {target}. Enter with: cd {target} && snug -d')
    print('Commit flake.nix and flake.lock with your project for reproducible environments.')
    return 0


def develop(arguments):
    if arguments[:1] == ['init']:
        if len(arguments) not in (2, 3):
            raise SnugError('Usage: snug -d init python|node|rust [directory]')
        return initialize(arguments[1], arguments[2] if len(arguments) == 3 else '.')
    if not Path('flake.nix').is_file():
        raise SnugError('No flake.nix here. Start with snug -d init python (or node/rust).')
    # Explicit path works even before git add; avoids hidden untracked-file failures.
    project = 'path:' + str(Path.cwd())
    if arguments == ['update']:
        run(NIX + ['flake', 'update', '--flake', project])
    else:
        tail = arguments[1:] if arguments[:1] == ['--'] else arguments
        run(NIX + ['develop', project] + (['--command'] + tail if tail else []))
    return 0
