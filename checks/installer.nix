{pkgs, ...}:
pkgs.runCommand "sleepy-installer-tests" {
  nativeBuildInputs = [pkgs.python3 pkgs.dialog pkgs.util-linux pkgs.jq];
  SLEEPY_ZONEINFO = "${pkgs.tzdata}/share/zoneinfo";
  PYTHONTZPATH = "${pkgs.tzdata}/share/zoneinfo";
} ''
  cp -r ${../packages/sleepy-installer} installer
  chmod -R u+w installer
  python3 -m unittest discover -s installer -v
  cp -r ${../packages/sleepy-system} system-tools
  chmod -R u+w system-tools
  python3 -m unittest discover -s system-tools -v
  cp -r ${../packages/sleepy-update} updater
  chmod -R u+w updater
  python3 -m unittest discover -s updater -v
  touch "$out"
''
