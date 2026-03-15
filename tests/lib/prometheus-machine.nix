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
  imports = [
    (import ./base-machine.nix {inherit ntfy-tester grafana-to-ntfy;})
  ];

  environment.systemPackages = [prometheus];

  services.prometheus = {
    enable = true;
    package = prometheus;

    # @NOTE: Short evaluation interval for fast test feedback. Prometheus will check
    #  alert rules every 5s and send fired alerts to the configured alertmanager.
    globalConfig.evaluation_interval = "5s";

    alertmanagers = [
      {
        static_configs = [
          {targets = ["${c.host}:${c.alertmanager-port}"];}
        ];
      }
    ];

    # @NOTE: Always-firing alert rule. vector(1) is Prometheus's equivalent of Grafana's
    #  "1==1" — a constant expression that always evaluates true. With no 'for' period,
    #  the alert fires on the first evaluation cycle (~5s).
    rules = [
      (builtins.toJSON {
        groups = [
          {
            name = "test-alerts";
            rules = [
              {
                alert = "TestAlert";
                expr = "vector(1)";
              }
            ];
          }
        ];
      })
    ];

    alertmanager = {
      enable = true;
      port = pkgs.lib.strings.toInt c.alertmanager-port;
      configuration = {
        route = {
          receiver = "grafana-to-ntfy-webhook";
          group_wait = "0s";
        };
        receivers = [
          {
            name = "grafana-to-ntfy-webhook";
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
}
