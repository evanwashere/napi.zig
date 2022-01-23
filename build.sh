#!/bin/sh

clear

zig build-lib \
-lc \
--strip \
-dynamic \
-OReleaseSafe \
-femit-bin=lib.node \
-fallow-shlib-undefined \
-isystem $(brew --prefix node)/include/node \
\
lib.zig $@

# -flto \ # -flto is not supported on macos