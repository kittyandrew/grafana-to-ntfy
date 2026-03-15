{
  ntfy-tester,
  grafana-to-ntfy,
  ...
}: let
  c = import ./config.nix;
in {
  imports = [
    (import ./common-machine.nix {inherit ntfy-tester;})
  ];

  systemd.services.grafana-to-ntfy = {
    enable = true;
    script = "${grafana-to-ntfy}/bin/grafana-to-ntfy";
    wantedBy = ["multi-user.target"];
    environment = {
      ROCKET_PORT = c.gtn-port;
      NTFY_URL = "http://${c.host}:${c.ntfy-port}/${c.topic}";
      BAUTH_USER = c.user;
      BAUTH_PASS = c.pass;
    };
  };
}
