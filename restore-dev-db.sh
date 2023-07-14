#!/usr/bin/env bash

sudo -u postgres psql -c "DROP DATABASE isre1late;"

unzstd --stdout isre1late.sql.zstd | pv | sudo -u postgres psql
