(import ./lib/lib.nix) {
  name = "prometheus-minimal-test";

  nodes = {
    primary = import ./lib/prometheus-machine.nix;
  };

  testScript = let
    c = import ./lib/config.nix;
  in ''
    primary.wait_for_unit("ntfy-sh")
    primary.wait_for_open_port(${c.ntfy-port})
    primary.wait_for_unit("grafana-to-ntfy")
    primary.wait_for_open_port(${c.gtn-port})
    primary.wait_for_unit("alertmanager")
    primary.wait_for_open_port(${c.alertmanager-port})
    primary.succeed("prometheus --version | head -n1 > /tmp/metadata.txt")
    primary.succeed("ntfy-tester-py")
  '';
}
