// 非掲載証明 PoC：証明の生成・検証、性能計測、古いルート攻撃の再現
import { buildPoseidon } from "circomlibjs";
import * as snarkjs from "snarkjs";
import fs from "fs";
import crypto from "crypto";

const poseidon = await buildPoseidon();
const F = poseidon.F;
const H = (arr) => F.toObject(poseidon(arr));
const MAX = (1n << 252n) - 1n;
const rand160 = () => BigInt("0x" + crypto.randomBytes(20).toString("hex"));

function buildTree(leaves, depth) {
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
function sortedList(list, depth) {
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
function indexedList(list, depth) {
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

const str = (o) => JSON.parse(JSON.stringify(o, (_, v) => (typeof v === "bigint" ? v.toString() : v)));
const results = [];

async function setup(name) {
  const zkey = `out/${name}.zkey`;
  if (!fs.existsSync(zkey)) await snarkjs.zKey.newZKey(`out/${name}.r1cs`, "pot15.ptau", zkey);
  const vkey = await snarkjs.zKey.exportVerificationKey(zkey);
  return { wasm: `out/${name}_js/${name}.wasm`, zkey, vkey };
}

async function prove(k, input) {
  const t0 = performance.now();
  const { proof, publicSignals } = await snarkjs.groth16.fullProve(str(input), k.wasm, k.zkey);
  const tp = performance.now() - t0;
  const t1 = performance.now();
  const ok = await snarkjs.groth16.verify(k.vkey, publicSignals, proof);
  return { proof, publicSignals, ok, tp, tv: performance.now() - t1 };
}

// 性能計測（リスト規模は OFAC SDN のデジタル通貨アドレス数程度を想定して 1,000 件）
for (const depth of [10, 20]) {
  for (const [scheme, build] of [["sorted", sortedList], ["indexed", indexedList]]) {
    const name = `${scheme}_d${depth}`;
    const k = await setup(name);
    const list = Array.from({ length: 1000 }, rand160);
    const L = build(list, depth);
    const times = [];
    let last;
    for (let r = 0; r < 5; r++) {
      const x = rand160();
      last = await prove(k, L.witness(x, rand160()));
      if (!last.ok) throw new Error("verify failed");
      times.push(last.tp);
    }
    times.sort((a, b) => a - b);
    const r1cs = await snarkjs.r1cs.info(`out/${name}.r1cs`);
    results.push({ name, constraints: r1cs.nConstraints, proveMsMedian: Math.round(times[2]), verifyMs: Math.round(last.tv) });
  }
}
console.log("== 性能（Groth16, snarkjs/wasm, 5回の中央値）");
console.table(results);

// 古いルート攻撃の再現（方式B, depth 10）
console.log("\n== 古いルート攻撃の再現");
const k = await setup("indexed_d10");
const list0 = Array.from({ length: 900 }, rand160);
const alice = rand160(); // 攻撃者
const L0 = indexedList(list0, 10);
const p = await prove(k, L0.witness(alice, 12345n));
console.log("t0: 旧リストで Alice の非掲載証明を生成・検証 →", p.ok);

// 検証コントラクトのモデル：直近 N 個のルートを許容（Tornado Cash: 30, Privacy Pools の state root: 64）
class Verifier {
  constructor(N) { this.N = N; this.roots = []; }
  publish(root) { this.roots.push(root); if (this.roots.length > this.N) this.roots.shift(); }
  async accept(pr) { return this.roots.includes(BigInt(pr.publicSignals[0])) && (await snarkjs.groth16.verify(k.vkey, pr.publicSignals, pr.proof)); }
}
const vN = new Verifier(30), v1 = new Verifier(1);
vN.publish(L0.root); v1.publish(L0.root);

const L1 = indexedList([...list0, alice], 10); // Alice が制裁リストに掲載される
vN.publish(L1.root); v1.publish(L1.root);
console.log("t1: Alice が掲載された新リストで証明を作れるか →", L1.witness(alice, 1n) !== null);
console.log("t1: 旧証明を『直近30ルート許容』の検証者に提出 →", await vN.accept(p), "（受理 = 攻撃成功）");
console.log("t1: 旧証明を『最新ルートのみ許容』の検証者に提出 →", await v1.accept(p));

// 掲載とは無関係な更新が続いた場合、何回の更新まで旧証明が通るか
let n = 1, listK = [...list0, alice];
while (await vN.accept(p)) { listK.push(rand160()); vN.publish(indexedList(listK, 10).root); n++; }
console.log(`掲載後、旧証明は ${n - 1} 回目の更新まで受理され続けた（N=30 なら Δ = 更新 ${vN.N - 1} 回分）`);

// 不正な証明の試み：Alice を飛び越える「隣接していない」2枚の葉を使う（方式A）
const kS = await setup("sorted_d10");
const vals = [0n, ...[...list0, alice].sort((a, b) => (a < b ? -1 : 1)), MAX];
const ia = vals.indexOf(alice);
const S1 = sortedList([...list0, alice], 10);
const w = S1.witness(vals[ia - 1] + 1n === alice ? alice + 1n : vals[ia - 1] + 1n, 7n); // 正規の近傍の証人を借りる
Object.assign(w, { x: alice, addrCommitment: H([alice, 7n]), low: vals[ia - 1], high: vals[ia + 1] });
try { await snarkjs.groth16.fullProve(str(w), kS.wasm, kS.zkey); console.log("偽造: 成功してしまった（バグ）"); }
catch (e) { console.log("偽造: 掲載済みの Alice について隣接しない葉で証明 → 失敗（回路の制約で拒否）"); }

fs.writeFileSync("results.json", JSON.stringify(results, null, 2));
process.exit(0);
