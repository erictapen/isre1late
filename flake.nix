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
          server = let
            crates = import ./server/Cargo.nix { inherit pkgs; };
          in crates.workspaceMembers.isre1late-server.build;
          default = server;
        };
        apps = rec {
          hello = flake-utils.lib.mkApp { drv = self.packages.${system}.hello; };
          default = hello;
        };
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
    );
}
