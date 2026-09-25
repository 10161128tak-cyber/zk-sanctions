#!/usr/bin/env bash
# 回路を深さ 10 / 20 でコンパイルし、PoC 用の Powers of Tau (2^15) を作る
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p out
for d in 10 20; do
  for c in sorted indexed; do
    sed "s/DEPTH/$d/" circuits/${c}_nonmembership.circom > circuits/${c}_d$d.circom
    circom circuits/${c}_d$d.circom --r1cs --wasm --O2 -l node_modules -o out
  done
done
if [ ! -f pot15.ptau ]; then
  npx snarkjs powersoftau new bn128 15 pot_0.ptau
  npx snarkjs powersoftau contribute pot_0.ptau pot_1.ptau --name=poc -e="poc entropy"
  npx snarkjs powersoftau prepare phase2 pot_1.ptau pot15.ptau
  rm -f pot_0.ptau pot_1.ptau
fi
