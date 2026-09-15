{
  pkgs,
  package ? pkgs.qt6.qtbase,
}:
# Private Qt ABI: re-audit this patch and replacement library on a Qt upgrade.
assert package.version == "6.11.1";
  package.overrideAttrs (old: {
    pname = "qtbase-wayland-focus-reset";
    patches = (old.patches or []) ++ [./qtbase-keyboard-focus-reset.patch];
    outputs = ["out"];
    separateDebugInfo = false;
    nativeBuildInputs = old.nativeBuildInputs ++ [pkgs.patchelf];
    buildPhase = ''
      runHook preBuild
      cmake --build . --target WaylandClient --parallel "$NIX_BUILD_CORES"
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/lib"
      cp -a lib/libQt6WaylandClient.so* "$out/lib/"
      patchelf --set-rpath "$(patchelf --print-rpath ${package}/lib/libQt6WaylandClient.so.6.11.1)" \
        "$out/lib/libQt6WaylandClient.so.6.11.1"
      runHook postInstall
    '';
    postFixup = "";
    moveToDev = [];
    setupHook = null;
  })
