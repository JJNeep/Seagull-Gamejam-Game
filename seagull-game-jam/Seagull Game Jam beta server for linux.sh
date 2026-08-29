#!/bin/sh
printf '\033c\033]0;%s\a' Seagull Game Jam
base_path="$(dirname "$(realpath "$0")")"
"$base_path/Seagull Game Jam beta server for linux.x86_64" "$@"
