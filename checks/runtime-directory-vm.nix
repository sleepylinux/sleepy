{
  pkgs,
  homeConfig,
}: let
  # Real systemd directory lifecycle, with harmless servers instead of invoking
  # a secure locker. Exercise both stop/start directions without acquiring a lock.
  server = pkgs.writeText "runtime-peer.py" ''
    import os, socket, sys
    path = os.path.join(os.environ["RUNTIME_DIRECTORY"], sys.argv[1])
    try:
        os.unlink(path)
    except FileNotFoundError:
        pass
    listener = socket.socket(socket.AF_UNIX)
    listener.bind(path)
    listener.listen()
    while True:
        peer, _ = listener.accept()
        with peer:
            peer.sendall(b"alive")
  '';
  probe = pkgs.writeText "runtime-probe.py" ''
    import socket, sys
    with socket.socket(socket.AF_UNIX) as peer:
        peer.settimeout(5)
        peer.connect(sys.argv[1])
        assert peer.recv(5) == b"alive"
  '';
  service = name: unit: {
    wantedBy = ["default.target"];
    serviceConfig = {
      inherit (unit.Service) RuntimeDirectory RuntimeDirectoryMode RuntimeDirectoryPreserve;
      ExecStart = "${pkgs.python3}/bin/python3 ${server} ${name}.sock";
    };
  };
in
  pkgs.testers.runNixOSTest {
    name = "sleepy-shared-runtime-directory";
    nodes.machine = {
      users.users.peer = {
        isNormalUser = true;
        linger = true;
      };
      systemd.user.services = {
        session-peer = service "session" homeConfig.systemd.user.services.sleepy-session;
        locker-peer = service "locker" homeConfig.systemd.user.services.sleepy-locker;
      };
    };
    testScript = ''
      start_all()
      uid = machine.succeed("id -u peer").strip()
      runtime = f"/run/user/{uid}"
      user = f"sudo -u peer XDG_RUNTIME_DIR={runtime} DBUS_SESSION_BUS_ADDRESS=unix:path={runtime}/bus"
      machine.wait_until_succeeds(f"test -S {runtime}/sleepy/session.sock && test -S {runtime}/sleepy/locker.sock")
      machine.succeed(f"test $(stat -c %a {runtime}/sleepy) = 700")
      machine.succeed(f"test $(stat -c %u {runtime}/sleepy) = {uid}")
      for stopping, survivor in [("session", "locker"), ("locker", "session")]:
          socket_path = f"{runtime}/sleepy/{survivor}.sock"
          inode = machine.succeed(f"stat -c %i {socket_path}").strip()
          pid = machine.succeed(f"{user} systemctl --user show {survivor}-peer -P MainPID").strip()
          machine.succeed(f"{user} systemctl --user stop {stopping}-peer")
          assert machine.succeed(f"stat -c %i {socket_path}").strip() == inode
          machine.succeed(f"{user} ${pkgs.python3}/bin/python3 ${probe} {socket_path}")
          machine.succeed(f"{user} systemctl --user start {stopping}-peer")
          machine.wait_until_succeeds(f"{user} ${pkgs.python3}/bin/python3 ${probe} {runtime}/sleepy/{stopping}.sock")
          assert machine.succeed(f"stat -c %i {socket_path}").strip() == inode
          assert machine.succeed(f"{user} systemctl --user show {survivor}-peer -P MainPID").strip() == pid
          machine.succeed(f"{user} ${pkgs.python3}/bin/python3 ${probe} {socket_path}")
      machine.succeed(f"{user} systemctl --user stop session-peer locker-peer")
      machine.succeed(f"test -d {runtime}/sleepy")
    '';
  }
