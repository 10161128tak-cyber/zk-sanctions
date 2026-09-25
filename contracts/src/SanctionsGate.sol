// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IGroth16Verifier {
    function verifyProof(
        uint256[2] calldata a,
        uint256[2][2] calldata b,
        uint256[2] calldata c,
        uint256[2] calldata pubSignals
    ) external view returns (bool);
}

/// @title 制裁リスト非掲載証明のゲート（共通部分）
/// @notice リスト管理者がルートを投稿し、利用者は非掲載証明を添えて操作する。
///         どの古いルートを受理するか（= 猶予期間Δ）だけを派生コントラクトで差し替える。
///         公開入力は [root, addrCommitment]。
abstract contract SanctionsGate {
    IGroth16Verifier public immutable verifier;
    address public immutable listManager;
    uint256 public currentRoot;

    event RootPublished(uint256 indexed root, uint256 timestamp);

    error NotListManager();
    error RootNotAccepted();
    error InvalidProof();

    constructor(IGroth16Verifier _verifier, address _listManager) {
        verifier = _verifier;
        listManager = _listManager;
    }

    /// @notice リスト更新：新しいルートを投稿する
    function publishRoot(uint256 root) external {
        if (msg.sender != listManager) revert NotListManager();
        _onPublish(currentRoot, root);
        currentRoot = root;
        emit RootPublished(root, block.timestamp);
    }

    /// @notice 非掲載証明を検証する（実際の送金処理の前段を想定）
    function checkNotSanctioned(
        uint256[2] calldata a,
        uint256[2][2] calldata b,
        uint256[2] calldata c,
        uint256[2] calldata pubSignals
    ) external view returns (bool) {
        if (!_isAcceptedRoot(pubSignals[0])) revert RootNotAccepted();
        if (!verifier.verifyProof(a, b, c, pubSignals)) revert InvalidProof();
        return true;
    }

    function _onPublish(uint256 oldRoot, uint256 newRoot) internal virtual;

    function _isAcceptedRoot(uint256 root) internal view virtual returns (bool);
}

/// @notice ベースライン1: 最新のルートのみ受理（Privacy Pools の ASP ルート）。Δ = 投稿の遅れのみ。
contract LatestOnlyGate is SanctionsGate {
    constructor(IGroth16Verifier v, address m) SanctionsGate(v, m) {}

    function _onPublish(uint256, uint256) internal override {}

    function _isAcceptedRoot(uint256 root) internal view override returns (bool) {
        return root != 0 && root == currentRoot;
    }
}

/// @notice ベースライン2: 直近 N 個のルートを受理（Tornado Cash: N = 30）。
///         Δ = 掲載後 N-1 回の更新にかかる時間で、実時間では上界がない。
contract RootHistoryGate is SanctionsGate {
    uint256 public immutable historySize;
    uint256[] internal roots;
    uint256 internal nextIndex;

    constructor(IGroth16Verifier v, address m, uint256 n) SanctionsGate(v, m) {
        historySize = n;
        roots = new uint256[](n);
    }

    function _onPublish(uint256, uint256 newRoot) internal override {
        roots[nextIndex] = newRoot;
        nextIndex = (nextIndex + 1) % historySize;
    }

    function _isAcceptedRoot(uint256 root) internal view override returns (bool) {
        if (root == 0) return false;
        for (uint256 i = 0; i < historySize; i++) {
            if (roots[i] == root) return true;
        }
        return false;
    }
}

/// @notice 時間窓（エポック）方式: 置き換えられてから window 秒未満のルートを受理（Semaphore v4 と同じ規則）。
///         Δ ≤ 投稿の遅れ + window と、実時間で上界を持つ。
contract TimeWindowGate is SanctionsGate {
    uint256 public immutable window;
    mapping(uint256 => uint256) public supersededAt;

    constructor(IGroth16Verifier v, address m, uint256 w) SanctionsGate(v, m) {
        window = w;
    }

    function _onPublish(uint256 oldRoot, uint256) internal override {
        if (oldRoot != 0) supersededAt[oldRoot] = block.timestamp;
    }

    function _isAcceptedRoot(uint256 root) internal view override returns (bool) {
        if (root == 0) return false;
        if (root == currentRoot) return true;
        uint256 t = supersededAt[root];
        return t != 0 && block.timestamp - t < window;
    }
}
