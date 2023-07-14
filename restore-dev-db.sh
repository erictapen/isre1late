#!/usr/bin/env bash

sudo -u postgres psql -c "DROP DATABASE isre1late;"

sudo systemctl restart postgresql.service

unzstd --stdout isre1late.sql.zstd | pv | psql
