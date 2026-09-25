# 非掲載証明ゲートの Solidity 実装と Foundry テスト

`circom-poc` の Indexed Merkle tree（深さ20）回路の Groth16 検証器を使い、
「どの古いルートを受理するか」だけが違う3つのゲートを比べる。

| コントラクト | 受理するルート | Δ（掲載から旧証明が通らなくなるまで） |
|---|---|---|
| `LatestOnlyGate` | 最新のみ（Privacy Pools の ASP ルート） | 投稿の遅れのみ |
| `RootHistoryGate(N)` | 直近 N 個（Tornado Cash: N=30） | 掲載後 N−1 回の更新にかかる時間（実時間の上界なし） |
| `TimeWindowGate(W)` | 置き換えから W 秒未満（Semaphore v4 と同じ規則） | 投稿の遅れ + W |

## テスト（`test/StaleProof.t.sol`）
掲載前のルートで作った Alice の証明を、Alice 掲載後に提出するシナリオ。
- `LatestOnly` は拒否、`RootHistory(30)` は掲載後29回目の更新まで受理、`TimeWindow(1h)` は置き換えから 3599 秒までは受理・3600 秒で拒否。
- 公開入力（コミットメント）を書き換えた証明は拒否。

## 実行
```bash
# 前提: Foundry、circom-poc で npm run build 済み
cd ../circom-poc && node gen_fixture.mjs   # 検証器 src/Groth16Verifier.sol と test/fixtures/stale_proof.json を生成
cd ../contracts && forge test --isolate -vv
```
- ガスは `--isolate`（外部呼び出しごとに別トランザクション扱い）で `vm.lastCallGas()` を読んだ値。
- この環境では solc の自動ダウンロードができなかったため、`forge test --use <solc 0.8.28 のパス>` で実行した。
- `lib/forge-std` は v1.9.7 をそのまま同梱している。
