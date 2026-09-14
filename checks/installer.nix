{pkgs, ...}:
pkgs.runCommand "sleepy-installer-tests" {
  nativeBuildInputs = [pkgs.python3 pkgs.dialog];
  SLEEPY_ZONEINFO = "${pkgs.tzdata}/share/zoneinfo";
  PYTHONTZPATH = "${pkgs.tzdata}/share/zoneinfo";
} ''
  cp -r ${../packages/sleepy-installer} installer
  chmod -R u+w installer
  python3 -m unittest discover -s installer -v
  touch "$out"
''
