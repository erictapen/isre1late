#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2023 2023 Kerstin Humm <mail@erictapen.name>
#
# SPDX-License-Identifier: GPL-3.0-or-later

sudo -u postgres psql -c "DROP DATABASE isre1late;"

sudo systemctl restart postgresql.target

unzstd --stdout ~/backup/hetzner6/var/backup/postgresql/isre1late.sql.zstd | pv | psql
