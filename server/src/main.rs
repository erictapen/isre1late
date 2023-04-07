// SPDX-FileCopyrightText: 2020 Kerstin Humm <mail@erictapen.name>
//
// SPDX-License-Identifier: GPL-3.0-or-later

use docopt::Docopt;
use rusqlite::{params, Connection};
use serde::Deserialize;
use std::path::PathBuf;

const USAGE: &'static str = "
Usage: isre1late-server --db <db> --port <port>
       isre1late-server --help

Options:
    -h, --help           Show this message.
    --db <db>            Path to sqlite database.
    --port <port>        TCP port on which the server listens.
";

#[derive(Deserialize)]
struct CliArgs {
    flag_db: PathBuf,
    flag_port: u16,
}

const trips_basepath: &'static str = "https://v6.vbb.transport.rest/trips";

fn main() {
    let args: CliArgs = Docopt::new(USAGE)
        .and_then(|d| d.deserialize())
        .unwrap_or_else(|e| e.exit());

    println!("Hello, world!");
}
