// SPDX-FileCopyrightText: 2020 Kerstin Humm <mail@erictapen.name>
//
// SPDX-License-Identifier: GPL-3.0-or-later

use docopt::Docopt;
use rusqlite::{params, Connection};
use serde::Deserialize;
use std::error::Error;
use std::path::PathBuf;

mod transport_rest_vbb_v6;
use transport_rest_vbb_v6::Trips;

const USAGE: &'static str = "
Usage: isre1late-server --db <db> --port <port>
       isre1late-server --help

Options:
    -h, --help           Show this message.
    --db <db>            Path to sqlite database. [default: ./db.sqlite]
    --port <port>        TCP port on which the server listens. [default: 8080]
";

#[derive(Deserialize)]
struct CliArgs {
    flag_db: Option<PathBuf>,
    flag_port: Option<u16>,
}

const trips_basepath: &'static str = "https://v6.vbb.transport.rest/trips";

fn main() -> Result<(), Box<dyn Error>> {
    let args: CliArgs = Docopt::new(USAGE)
        .and_then(|d| d.deserialize())
        .unwrap_or_else(|e| e.exit());

    let response = reqwest::blocking::get(trips_basepath)?;
    println!("{:#?}", response.json::<Trips>());

    Ok(())
}
