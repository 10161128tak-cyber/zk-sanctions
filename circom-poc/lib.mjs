import { buildPoseidon } from "circomlibjs";
import crypto from "crypto";

export const poseidon = await buildPoseidon();
export const F = poseidon.F;
export const H = (arr) => F.toObject(poseidon(arr));
export const MAX = (1n << 252n) - 1n;
export const rand160 = () => BigInt("0x" + crypto.randomBytes(20).toString("hex"));

export function buildTree(leaves, depth) {
  const n = 1 << depth;
  if (leaves.length > n) throw new Error("tree too small");
  const layers = [leaves.concat(Array(n - leaves.length).fill(0n))];
  for (let d = 0; d < depth; d++) {
    const prev = layers[d], next = [];
    for (let i = 0; i < prev.length; i += 2) next.push(H([prev[i], prev[i + 1]]));
    layers.push(next);
  }
  return { root: layers[depth][0], path: (idx) => layers.slice(0, depth).map((l, d) => l[(idx >> d) ^ 1]) };
}

// 方式A: Sorted Merkle tree（葉 = H(value)、番兵 0 と MAX を両端に置く）
export function sortedList(list, depth) {
  const vals = [0n, ...[...new Set(list)].sort((a, b) => (a < b ? -1 : 1)), MAX];
  const tree = buildTree(vals.map((v) => H([v])), depth);
  return { root: tree.root, witness(x, blinding) {
    const i = vals.findIndex((v, k) => v < x && x < vals[k + 1]);
    if (i < 0) return null; // 掲載されている → 正直には証明できない
    return { root: tree.root, addrCommitment: H([x, blinding]), x, blinding, low: vals[i], high: vals[i + 1],
             lowIndex: i, lowPath: tree.path(i), highPath: tree.path(i + 1) };
  } };
}

// 方式B: Indexed Merkle tree（葉 = H(value, nextValue)）
export function indexedList(list, depth) {
  const vals = [0n, ...[...new Set(list)].sort((a, b) => (a < b ? -1 : 1)), MAX];
  const leaves = vals.slice(0, -1).map((v, k) => H([v, vals[k + 1]]));
  const tree = buildTree(leaves, depth);
  return { root: tree.root, witness(x, blinding) {
    const i = vals.findIndex((v, k) => v < x && x < vals[k + 1]);
    if (i < 0) return null;
    return { root: tree.root, addrCommitment: H([x, blinding]), x, blinding, lowValue: vals[i], lowNext: vals[i + 1],
             lowIndex: i, lowPath: tree.path(i) };
  } };
}

export const str = (o) => JSON.parse(JSON.stringify(o, (_, v) => (typeof v === "bigint" ? v.toString() : v)));
