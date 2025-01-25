(import ./lib/lib.nix) {
  name = "grafana-minimal-test";

  nodes = {
    primary = import ./lib/grafana-machine.nix;
  };

  testScript = let
    c = import ./lib/config.nix;
  in ''
    primary.wait_for_unit("ntfy-sh")
    primary.wait_for_open_port(${c.ntfy-port})
    primary.wait_for_unit("grafana-to-ntfy")
    primary.wait_for_open_port(${c.gtn-port})
    primary.wait_for_unit("grafana")
    primary.wait_for_open_port(${c.grafana-port})
    primary.succeed("grafana --version > /tmp/metadata.txt")
    primary.succeed("ntfy-tester-py")
  '';
}
