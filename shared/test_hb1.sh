#!/usr/bin/env bash
# Ejecuta el enlace de contrato RTL -> C del puente -> parser JVM.
set -euo pipefail
cd "$(dirname "$0")/.."
out="$PWD/shared/build/hb1"
mkdir -p "$out"

iverilog -g2005 -s tb_hb1_uart -Ptb_hb1_uart.CONTRACT=1 -o "$out/uart.vvp" \
    fpga/tb/tb_hb1_uart.v fpga/rtl/{bin_to_bcd,hb1_framer,uart_tx}.v
vvp -n "$out/uart.vvp" +FRAMES_OUT="$out/rtl.txt" | tee "$out/rtl.log"
grep -q '^PASS: 100 tramas' "$out/rtl.log"
"${CC:-cc}" -std=c11 -Wall -Wextra -Werror -Iesp32/main \
    esp32/main/hb1_framing.c esp32/tests/hb1_test.c -o "$out/bridge-test"
"$out/bridge-test" "$out/rtl.txt" "$out/notifications.txt"

cd mobile
./gradlew :app:testDebugUnitTest -Phb1ContractDir="$out" "$@"
