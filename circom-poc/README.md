# Circom による制裁リスト非掲載証明 PoC

小さなリスト（1,000 件）に対して「自分のアドレス x はリストに載っていない」ことを ZK で証明し、
あわせて**古いルートを許容する検証者に対する攻撃**を再現した。

## 2つの方式
| | 方式A: Sorted Merkle tree | 方式B: Indexed Merkle tree（Aztec 方式） |
|---|---|---|
| 葉 | `Poseidon(value)` を昇順に並べる | `Poseidon(value, nextValue)` |
| 番兵 | 両端に 0 と 2^252−1 | 同じ |
| 証明内容 | 隣り合う2枚の葉 low, high（位置 i, i+1）で low < x < high | 1枚の葉で value < x < nextValue |
| Merkle パス | 2本 | 1本 |
| ファイル | `circuits/sorted_nonmembership.circom` | `circuits/indexed_nonmembership.circom` |

共通:
- 公開入力は `root`（リストのルート）と `addrCommitment = Poseidon(x, blinding)`。x 自体は秘密。取引との結び付けはコミットメントで行う想定。
- 大小比較の健全性のため、x と葉の値を 252 ビットに制限（`Num2Bits(252)`）。
- 方式Aの隣接性は `Num2Bits(depth)` に `lowIndex` と `lowIndex+1` を入れ、それぞれのビット列でパスを計算することで保証。

## 結果（Groth16, snarkjs 0.7.6 / wasm, 2026-09-25 実行, 5回の中央値）
| 回路 | 深さ（最大葉数） | 制約数 | 証明生成 | 検証 |
|---|---|---|---|---|
| 方式A | 10（1,024） | 6,786 | 525 ms | 14 ms |
| 方式B | 10（1,024） | 4,170 | 426 ms | 30 ms |
| 方式A | 20（約100万） | 11,646 | 934 ms | 18 ms |
| 方式B | 20（約100万） | 6,600 | 558 ms | 18 ms |

- 方式B は Merkle パスが1本なので、深さ20で制約数が約 43% 少ない。以後のベースラインは方式Bを使うのがよさそう。
- 検証時間は Groth16 なので回路規模にほぼ依存しない（計測値の差はノイズ）。証明サイズも一定（G1×2, G2×1）。
- 環境はクラウドのコンテナ（CPU 詳細未記録）。論文用の数値は、固定したマシンで取り直すこと。
- 信頼できるセットアップは PoC 用にその場で生成したもの（本番では使えない）。

## 古いルート攻撃の再現（`run.mjs` 後半、出力は `run_output.txt`）
1. t0: 900 件のリスト L0 で、攻撃者 Alice が非掲載証明を作る → 検証 OK
2. t1: Alice がリストに追加され L1 に更新 → **L1 に対しては証明を作れない**（正しい）
3. t1: 旧証明を「直近30ルート許容」（Tornado 型）の検証者に出す → **受理（攻撃成功）**
4. t1: 旧証明を「最新ルートのみ許容」の検証者に出す → 拒否
5. 掲載後に無関係な更新が続いても、旧証明は **29 回目の更新まで受理され続けた**
6. 追加確認: 掲載済みの Alice について、隣接しない2枚の葉（Alice を飛び越える）で証明を作ろうとすると、回路の制約で失敗する

→ 回路自体は正しく、問題は**検証者がどのルートを許すか**（= Δ）にあることが確認できた。

## 動かし方
```bash
# 前提: circom 2.2.2（cargo install --git https://github.com/iden3/circom.git --tag v2.2.2 circom）, Node.js 22
npm install
npm run build   # 回路4本のコンパイルと Powers of Tau（2^15）の生成
npm start       # 性能計測と古いルート攻撃の再現（結果は results.json）
```

## 次の一歩
- エポック方式: 公開入力に `epoch` を加え、検証者は「現在のエポックと1つ前」だけ許す → Δ を時間で上界化。
- Solidity 検証器を生成し、Foundry でガス代を測る（`snarkjs zkey export solidityverifier`）。
- リスト更新のコスト（ツリー再計算・ルート投稿のガス）の計測。
