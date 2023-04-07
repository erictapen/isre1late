# SPDX-FileCopyrightText: 2020 Kerstin Humm <mail@erictapen.name>
#
# SPDX-License-Identifier: GPL-3.0-or-later

{
  description = "Is RE1 late?";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    # We needed latest crate2nix for now.
    nixpkgs-crate2nix.url = "github:erictapen/nixpkgs/crate2nix";
  };

  outputs = { self, nixpkgs, flake-utils, nixpkgs-crate2nix }:
    flake-utils.lib.eachDefaultSystem (system:
      let pkgs = nixpkgs.legacyPackages.${system}; in
      {
        packages = rec {
          server =
            let
              crates = import ./server/Cargo.nix { inherit pkgs; };
            in
            crates.workspaceMembers.isre1late-server.build;
          default = server;
        };
        apps = rec {
          server = flake-utils.lib.mkApp { drv = self.packages.${system}.server; };
          default = server;
        };
        checks.reuse = pkgs.runCommand "reuse-check" { } ''
          ${pkgs.reuse}/bin/reuse --root ${self} lint && touch $out
        '';

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            nodejs
            cargo
            rustc
            sqlite
            pkg-config
            openssl
            (import nixpkgs-crate2nix { inherit system; }).crate2nix
            reuse
          ];
        };
      }
    ) // {
        nixosModules.default = {config, pkgs, lib, ... }: let
          package = self.packages.${config.nixpkgs.localSystem.system}.server;
          # A random port
          port = "28448";
          stateDir = "/var/lib/isre1late";
        in {

          systemd.services.isre1late = {
            description = "Is RE1 late?";
            after = [ "network.target" ];
            wantedBy = [ "multi-user.target" ];

            serviceConfig = {
              Type = "simple";
              ExecStart = ''
                ${package}/bin/isre1late-server \
                  --db ${stateDir}/db.sqlite \
                  --port ${port}
              '';
              Restart = "always";
              StateDirectory = "isre1late";
              User = "isre1late";
              Group = "isre1late";
            };

          };

          users.users.isre1late = {
            isSystemUser = true;
            home = stateDir;
            group = "isre1late";
          };
          users.groups.isre1late = { };

        };
    };
}
