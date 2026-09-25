// Solidity 検証器と Foundry テスト用の証明（古いルート攻撃のシナリオ）を生成する
// 前提: npm run build 済み（out/indexed_d20.* と pot15.ptau がある）
import * as snarkjs from "snarkjs";
import fs from "fs";
import { H, indexedList, str } from "./lib.mjs";

const name = "indexed_d20";
const zkey = `out/${name}.zkey`;
if (!fs.existsSync(zkey)) await snarkjs.zKey.newZKey(`out/${name}.r1cs`, "pot15.ptau", zkey);

// 検証器コントラクト
const templates = { groth16: fs.readFileSync("node_modules/snarkjs/templates/verifier_groth16.sol.ejs", "utf8") };
const sol = await snarkjs.zKey.exportSolidityVerifier(zkey, templates);
fs.writeFileSync("../contracts/src/Groth16Verifier.sol", sol);

// 決定的なリスト（再現性のため乱数を使わない）
const list0 = Array.from({ length: 900 }, (_, i) => H([BigInt(i)]) >> 94n); // 160 ビットに切り詰め
const alice = H([424242n]) >> 94n;
const blinding = 12345n;
const L0 = indexedList(list0, 20);
const L1 = indexedList([...list0, alice], 20); // Alice 掲載後

const { proof, publicSignals } = await snarkjs.groth16.fullProve(str(L0.witness(alice, blinding)), `out/${name}_js/${name}.wasm`, zkey);
const vkey = await snarkjs.zKey.exportVerificationKey(zkey);
if (!(await snarkjs.groth16.verify(vkey, publicSignals, proof))) throw new Error("verify failed");

// Solidity の verifyProof に渡す形（b は係数の順序が逆になる）
const fixture = {
  root0: L0.root.toString(),
  root1: L1.root.toString(),
  a: [proof.pi_a[0], proof.pi_a[1]],
  b: [[proof.pi_b[0][1], proof.pi_b[0][0]], [proof.pi_b[1][1], proof.pi_b[1][0]]],
  c: [proof.pi_c[0], proof.pi_c[1]],
  pubSignals: publicSignals,
};
fs.mkdirSync("../contracts/test/fixtures", { recursive: true });
fs.writeFileSync("../contracts/test/fixtures/stale_proof.json", JSON.stringify(fixture, null, 2));
console.log("wrote Groth16Verifier.sol and stale_proof.json; root0 =", fixture.root0);
process.exit(0);
