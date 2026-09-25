# zk-sanctions：ZKによる制裁リスト非掲載証明と「古い証明」問題

| ファイル | 内容 |
|---|---|
| `docs/01_privacy_pools_要点.md` | Privacy Pools 論文（Buterin et al.）の要点と、0xbow 実装での ASP ルートの扱い |
| `docs/02_ルート履歴調査.md` | Tornado Cash / Semaphore / Privacy Pools が古いルートをどう許容するか（コード確認） |
| `docs/03_研究の問い案.md` | 研究の問いの1文案5つとおすすめ |
| `docs/04_受理ルールとガス.md` | 古いルートの受理ルール3種のガスと、証明の失効率の見積もり |
| `docs/05_OFAC更新頻度.md` | OFAC SDN のデジタル通貨アドレスの更新頻度（2022–2026）と失効率の実データ見積もり |
| `circom-poc/` | Circom による非掲載証明（Sorted / Indexed Merkle tree）と古いルート攻撃の再現 |
| `contracts/` | 受理ルール3種の Solidity 実装と Foundry テスト |
