{pkgs}: let
  qt = pkgs.qt6.qtbase;
in
  assert qt.version == "6.11.1";
    qt.overrideAttrs (old: {
      pname = "qt-keyboard-capability-regression";
      patches = (old.patches or []) ++ [./keyboard-capability-regression.patch];
      outputs = ["out"];
      separateDebugInfo = false;
      buildInputs = old.buildInputs ++ [qt qt.dev];
      nativeBuildInputs = old.nativeBuildInputs ++ [qt.dev qt];
      postPatch =
        (old.postPatch or "")
        + ''
          printf '%s\n' 'add_subdirectory(wayland)' > tests/auto/CMakeLists.txt
          printf '%s\n' 'add_subdirectory(shared)' 'add_subdirectory(client)' > tests/auto/wayland/CMakeLists.txt
        '';
      cmakeFlags = [
        "-DQT_BUILD_STANDALONE_TESTS=ON"
        "-DQT_BUILD_TESTS=ON"
        "-DQT_BUILD_TESTS_BY_DEFAULT=OFF"
        "-DQT_BUILD_EXAMPLES=OFF"
        "-DQT_BUILD_BENCHMARKS=OFF"
        "-DQT_BUILD_MANUAL_TESTS=OFF"
        "-DQT_BUILD_CMAKE_PREFIX_PATH=${qt.dev}/lib/cmake"
      ];
      buildPhase = ''cmake --build . --target tst_client --parallel "$NIX_BUILD_CORES"'';
      installPhase = ''
        mkdir -p "$out/bin"
        cp tests/auto/wayland/client/tst_client "$out/bin/"
      '';
      postFixup = "";
      moveToDev = [];
      setupHook = null;
    })
