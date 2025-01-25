{
  pkgs,
  system,
  ntfy-tester,
  versioned-pkgs,
  grafana-to-ntfy,
  ...
}: let
  c = import ./config.nix;
  prometheus = versioned-pkgs.legacyPackages.${system}.prometheus;
in {
  environment.systemPackages = [ntfy-tester prometheus];
  environment.variables = {
    ALERTMANAGER_URL = "${c.host}:${c.alertmanager-port}";
    NTFY_URL = "${c.host}:${c.ntfy-port}/${c.topic}";
    BAUTH_USER = c.user;
    BAUTH_PASS = c.pass;
  };

  systemd.services.grafana-to-ntfy = {
    enable = true;
    script = "${grafana-to-ntfy}/bin/grafana-to-ntfy";
    wantedBy = ["multi-user.target"];
    environment = {
      LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [pkgs.openssl];
      NTFY_URL = "http://${c.host}:${c.ntfy-port}/${c.topic}";
      BAUTH_USER = c.user;
      BAUTH_PASS = c.pass;
    };
  };

  services = {
    ntfy-sh = {
      enable = true;
      settings = {
        base-url = "http://${c.host}";
        listen-http = ":${c.ntfy-port}";
      };
    };

    prometheus = {
      enable = true;
      package = prometheus;
      alertmanager = {
        enable = true;
        port = pkgs.lib.strings.toInt c.alertmanager-port;
        configuration = {
          route = {
            receiver = "non-existing-receiver";
            group_wait = "0s";
          };
          receivers = [
            {
              name = "non-existing-receiver";
              webhook_configs = [
                {
                  url = "http://${c.host}:${c.gtn-port}";
                  http_config = {
                    basic_auth = {
                      username = c.user;
                      password = c.pass;
                    };
                  };
                }
              ];
            }
          ];
        };
      };
    };
  };
}
