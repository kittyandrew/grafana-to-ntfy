# Source: https://blog.thalheim.io/2023/01/08/how-to-use-nixos-testing-framework-with-flakes/
# The first argument to this function is the test module itself
test:
# These arguments are provided by `flake.nix` on import, see checkArgs
{
  pkgs,
  system,
  versioned-pkgs,
  grafana-to-ntfy,
}: let
  ntfy-tester = pkgs.stdenv.mkDerivation {
    name = "ntfy-tester-py";
    buildInputs = [
      (pkgs.python3.withPackages
        (pythonPackages: with pythonPackages; [websocket-client requests]))
    ];
    unpackPhase = "true";
    installPhase = ''
      mkdir -p $out/bin
      cp ${./tester.py} $out/bin/ntfy-tester-py
      chmod +x $out/bin/ntfy-tester-py
    '';
  };
in
  pkgs.testers.runNixOSTest {
    node.specialArgs = {
      inherit system;
      inherit ntfy-tester;
      inherit versioned-pkgs;
      inherit grafana-to-ntfy;
    };
    # This makes `self` available in the NixOS configuration of our virtual machines.
    # This is useful for referencing modules or packages from your own flake
    # as well as importing from other flakes.
    imports = [test];
  }
