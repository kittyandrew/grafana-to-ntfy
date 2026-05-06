# Source: https://blog.thalheim.io/2023/01/08/how-to-use-nixos-testing-framework-with-flakes/
# The first argument to this function is the test module itself
test:
# These arguments are provided by `flake.nix` on import, see checkArgs
{
  pkgs,
  system,
  versioned-pkgs,
  grafana-to-ntfy,
  docker-image ? null,
}: let
  ntfy-tester = pkgs.stdenv.mkDerivation {
    name = "ntfy-tester-py";
    buildInputs = [
      (pkgs.python3.withPackages
        (pythonPackages: with pythonPackages; [websocket-client]))
    ];
    unpackPhase = "true";
    installPhase = ''
      mkdir -p $out/bin
      cp ${./tester.py} $out/bin/ntfy-tester-py
      chmod +x $out/bin/ntfy-tester-py
    '';
  };
in
  # @NOTE: Use the versioned nixpkgs's own testers so the NixOS module evaluation
  #  (services.grafana, services.prometheus, etc.) matches the package versions we're
  #  testing against. Using `pkgs.testers.runNixOSTest` (unstable) caused unstable's
  #  services.grafana module to be applied to older Grafana packages, breaking startup
  #  on Grafana 9.x-12.x when unstable moved to 13.x layout.
  #                                                            - andrew, May 6 2026
  versioned-pkgs.legacyPackages.${system}.testers.runNixOSTest {
    node.specialArgs = {
      inherit system;
      inherit ntfy-tester;
      inherit versioned-pkgs;
      inherit grafana-to-ntfy;
      inherit docker-image;
    };
    # This makes `self` available in the NixOS configuration of our virtual machines.
    # This is useful for referencing modules or packages from your own flake
    # as well as importing from other flakes.
    imports = [test];
  }
