#!/bin/sh

clear

zig build-lib \
--strip \
-dynamic \
-OReleaseSafe \
-femit-bin=lib.node \
-fallow-shlib-undefined \
\
lib.zig $@

# -flto \ # -flto is not supported on macos