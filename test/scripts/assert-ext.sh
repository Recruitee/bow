#!/bin/bash
set -e

touch "$2"
name=$(basename "$2")
ext="${name##*.}"
test "$ext" = "$3"
