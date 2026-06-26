# SPDX-FileCopyrightText: 2023 Kerstin Humm <mail@erictapen.name>
#
# SPDX-License-Identifier: GPL-3.0-or-later

{
  description = "How late is RE1?";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    {
      self,
      nixpkgs,
    }:
    let
      forEachSystem =
        f:
        nixpkgs.lib.genAttrs [
          "x86_64-linux"
          "aarch64-linux"
          "x86_64-darwin"
          "aarch64-darwin"
        ] f;
      nixpkgsFor = forEachSystem (
        system:
        import nixpkgs {
          inherit system;
        }
      );
    in

    {
      packages = forEachSystem (
        system:
        let
          pkgs = nixpkgsFor.${system};
        in
        {
          server =
            let
              crates = import ./server/Cargo.nix { inherit pkgs; };
            in
            crates.workspaceMembers.isre1late-server.build.override {
              runTests = true;
            };
          client = import ./client {
            inherit pkgs;
            inherit (self.packages.${system}) icons;
          };
          icons = pkgs.runCommand "icons" { nativeBuildInputs = [ pkgs.imagemagick ]; } ''
            ${import ./client/icons.nix pkgs}/bin/generate-icons.sh ${./client/icon.svg}

            mkdir -p $out
            cp -R . $out
          '';
          default = self.packages.${system}.server;
        }
      );

      checks = forEachSystem (
        system:
        let
          pkgs = nixpkgsFor.${system};
        in
        {
          reuse = pkgs.runCommand "reuse-check" { } ''
            ${pkgs.reuse}/bin/reuse --root ${self} lint && touch $out
          '';
          inherit (self.packages."${system}") client server;
        }
      );

      devShells = forEachSystem (
        system:
        let
          pkgs = nixpkgsFor.${system};
        in
        {
          default = pkgs.mkShell {
            buildInputs =
              with pkgs;
              [
                # Server
                nodejs
                cargo
                rustc
                clippy
                rustfmt
                diesel-cli
                pkg-config
                openssl
                postgresql
                libpq
                crate2nix
                reuse
                (python3.withPackages (ps: with ps; [ psycopg2 ]))
                websocat
              ]
              ++

                # Client
                (with pkgs.elmPackages; [
                  elm
                  elm-format
                  elm-test
                  elm-json
                  elm2nix
                  (python3.withPackages (ps: with ps; [ requests ]))
                  (import ./client/nginx.nix pkgs)
                ]);
            RUST_LOG = "info";
            DATABASE_URL = "postgres://localhost/isre1late?host=/run/postgresql";
            PGDATABASE = "isre1late";
            PGUSER = "isre1late";
            HAFAS_BASE_URL = "https://v6.vbb.transport.rest";
          };
        }
      );

      nixosModules.default =
        {
          config,
          pkgs,
          lib,
          ...
        }:
        let
          server = self.packages.${pkgs.stdenv.hostPlatform.system}.server;
          client = self.packages.${pkgs.stdenv.hostPlatform.system}.client;
          inherit (lib)
            mkEnableOption
            mkOption
            mkIf
            types
            ;
          cfg = config.services.isre1late;
        in
        {

          options.services.isre1late = {
            enable = mkEnableOption "IsRE1late server";
            port = mkOption {
              type = types.int;
              example = 8080;
              description = "TCP port to use.";
            };
            websocketPort = mkOption {
              type = types.int;
              example = 8081;
              description = "TCP port to use for the websocket server.";
            };
            hafasBaseUrl = mkOption {
              type = types.str;
              default = "https://v6.vbb.transport.rest";
              description = "Hafas Base URL without a leading slash.";
            };
          };

          config = mkIf cfg.enable {
            services.postgresql = {
              enable = true;
              ensureDatabases = [ "isre1late" ];
              ensureUsers = [
                {
                  name = "isre1late";
                  ensureDBOwnership = true;
                }
              ];
            };

            systemd.services.isre1late = {
              description = "How late is RE1?";
              after = [
                "network.target"
                "postgresql.target"
              ];
              requires = [ "postgresql.target" ];
              wantedBy = [ "multi-user.target" ];
              environment = {
                DATABASE_URL = "postgres://localhost/isre1late?host=/run/postgresql";
                HAFAS_BASE_URL = cfg.hafasBaseUrl;
              };

              serviceConfig = {
                Type = "simple";
                ExecStart = ''
                  ${server}/bin/isre1late-server \
                    --port ${builtins.toString cfg.port} \
                    --ws-port ${builtins.toString cfg.websocketPort}
                '';
                Restart = "always";
                RestartSec = "30s";
                User = "isre1late";
                Group = "isre1late";
              };
            };

            users.users.isre1late = {
              isSystemUser = true;
              group = "isre1late";
              packages = [ server ];
            };
            users.groups.isre1late = { };

            services.nginx.enable = true;
            services.nginx.virtualHosts."isre1late.erictapen.name" = {
              enableACME = true;
              forceSSL = true;
              locations = {
                "/" = {
                  root = client;
                  tryFiles = "/index.html =404";
                };
                "/assets/" = {
                  alias = client + "/assets/";
                };
                "/api".return = "301 /api/";
                "/api/" = {
                  proxyPass = "http://[::1]:${toString cfg.port}";
                  extraConfig = ''
                    gzip on;
                    gzip_types application/json;
                  '';
                };
                "/api/ws".return = "301 /api/ws/";
                "/api/ws/" = {
                  proxyPass = "http://[::1]:${toString cfg.websocketPort}";
                  extraConfig = ''
                    proxy_http_version 1.1;
                    proxy_set_header Upgrade $http_upgrade;
                    proxy_set_header Connection upgrade;
                  '';
                };
              };
            };

          };
        };
    };
}
