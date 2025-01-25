{
  pkgs,
  system,
  ntfy-tester,
  versioned-pkgs,
  grafana-to-ntfy,
  ...
}: let
  c = import ./config.nix;
in {
  environment.systemPackages = [ntfy-tester];
  environment.variables = {
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

    grafana = {
      enable = true;
      package = versioned-pkgs.legacyPackages.${system}.grafana;
      settings = {};
      provision = {
        alerting = {
          rules.settings = {
            apiVersion = 1;
            groups = [
              {
                orgId = 1;
                name = "my_rule_group_2";
                folder = "my_first_folder_2";
                interval = "10s";
                rules = [
                  {
                    uid = "my_id_2";
                    title = "my_first_rule_2";
                    condition = "A";
                    for = "0s";
                    labels.team = "sre_team1";
                    data = [
                      {
                        refId = "A";
                        datasourceUid = "__expr__";
                        model = {
                          conditions = [
                            {
                              evaluator = {
                                params = [0];
                                type = "gt";
                              };
                              operator.type = "and";
                              query.params = ["A"];
                              reducer.type = "last";
                              type = "query";
                            }
                          ];
                          datasource = {
                            type = "__expr__";
                            uid = "__expr__";
                          };
                          expression = "1==1";
                          intervalMs = 1000;
                          refId = "A";
                          type = "math";
                        };
                      }
                    ];
                  }
                ];
              }
            ];
          };

          contactPoints.settings = {
            apiVersion = 1;
            contactPoints = [
              {
                orgId = 1;
                name = "cp_webhook_rec";
                receivers = [
                  {
                    uid = "cp_webhook";
                    type = "webhook";
                    disableResolveMessage = false;
                    settings = {
                      url = "http://${c.host}:${c.gtn-port}";
                      httpMethod = "POST";
                      username = c.user;
                      password = c.pass;
                    };
                  }
                ];
              }
            ];
            deleteContactPoints = [
              {
                orgId = 1;
                uid = "";
              }
            ];
          };

          policies.settings = {
            apiVersion = 1;
            policies = [
              {
                orgId = 1;
                receiver = "cp_webhook_rec";
                group_by = ["..."];
                group_wait = "10s";
                group_interval = "1m";
                repeat_interval = "1m";
              }
            ];
          };
        };
      };
    };
  };
}
