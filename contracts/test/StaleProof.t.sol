// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {Groth16Verifier} from "../src/Groth16Verifier.sol";
import {
    IGroth16Verifier, SanctionsGate, LatestOnlyGate, RootHistoryGate, TimeWindowGate
} from "../src/SanctionsGate.sol";

/// Alice の非掲載証明（掲載前のルート root0 で作成）を、Alice 掲載後（root1）に提出するシナリオ。
contract StaleProofTest is Test {
    uint256[2] a;
    uint256[2][2] b;
    uint256[2] c;
    uint256[2] pub;
    uint256 root0;
    uint256 root1;
    IGroth16Verifier verifier;

    function setUp() public {
        string memory j = vm.readFile("test/fixtures/stale_proof.json");
        root0 = vm.parseJsonUint(j, ".root0");
        root1 = vm.parseJsonUint(j, ".root1");
        uint256[] memory x = vm.parseJsonUintArray(j, ".a");
        a = [x[0], x[1]];
        x = vm.parseJsonUintArray(j, ".b[0]");
        b[0] = [x[0], x[1]];
        x = vm.parseJsonUintArray(j, ".b[1]");
        b[1] = [x[0], x[1]];
        x = vm.parseJsonUintArray(j, ".c");
        c = [x[0], x[1]];
        x = vm.parseJsonUintArray(j, ".pubSignals");
        pub = [x[0], x[1]];
        verifier = IGroth16Verifier(address(new Groth16Verifier()));
        vm.warp(1_000_000);
    }

    function _check(SanctionsGate g) internal view returns (bool ok, uint256 gasUsed) {
        uint256 g0 = gasleft();
        try g.checkNotSanctioned(a, b, c, pub) returns (bool r) {
            ok = r;
        } catch {
            ok = false;
        }
        gasUsed = g0 - gasleft();
    }

    function test_ProofValidOnRoot0() public {
        LatestOnlyGate g = new LatestOnlyGate(verifier, address(this));
        g.publishRoot(root0);
        (bool ok, uint256 gasUsed) = _check(g);
        assertTrue(ok);
        console.log("verify gas (LatestOnly, fresh root):", gasUsed);
    }

    function test_TamperedProofRejected() public {
        LatestOnlyGate g = new LatestOnlyGate(verifier, address(this));
        g.publishRoot(root0);
        pub[1] = pub[1] + 1; // 別のアドレスのコミットメントにすり替え
        (bool ok,) = _check(g);
        assertFalse(ok);
    }

    function test_LatestOnly_RejectsStaleProof() public {
        LatestOnlyGate g = new LatestOnlyGate(verifier, address(this));
        g.publishRoot(root0);
        g.publishRoot(root1);
        (bool ok,) = _check(g);
        assertFalse(ok);
    }

    function test_RootHistory_AcceptsStaleProofForNMinus1Updates() public {
        uint256 n = 30;
        RootHistoryGate g = new RootHistoryGate(verifier, address(this), n);
        g.publishRoot(root0);
        g.publishRoot(root1); // Alice 掲載
        (bool ok,) = _check(g);
        assertTrue(ok, "stale proof accepted right after listing");
        // 掲載後の更新（無関係な追加）を重ねる。root0 を含め n 個までは受理され続ける
        uint256 extra;
        while (true) {
            g.publishRoot(uint256(keccak256(abi.encode(extra))));
            extra++;
            (ok,) = _check(g);
            if (!ok) break;
        }
        // 掲載の更新を1回目として数えると、n-1 回目の更新まで受理
        assertEq(extra + 1, n);
        console.log("RootHistory(N=30): stale proof accepted until update #", extra);
    }

    function test_TimeWindow_AcceptsStaleProofForWindow() public {
        uint256 w = 1 hours;
        TimeWindowGate g = new TimeWindowGate(verifier, address(this), w);
        g.publishRoot(root0);
        g.publishRoot(root1); // Alice 掲載、root0 はこの時刻に置き換え
        (bool ok,) = _check(g);
        assertTrue(ok, "accepted inside window");
        vm.warp(block.timestamp + w - 1);
        (ok,) = _check(g);
        assertTrue(ok, "accepted at window - 1s");
        vm.warp(block.timestamp + 1);
        (ok,) = _check(g);
        assertFalse(ok, "rejected at window");
    }

    /// ガス計測は `forge test --isolate` で実行する（各外部呼び出しを別トランザクションとして扱い、
    /// ストレージのコールド/ウォームを実際に近づけるため）。値は calldata 等の固定費を除く実行ガス。
    function _measure(SanctionsGate g, string memory name) internal {
        g.publishRoot(1);
        g.publishRoot(root0);
        uint256 pubGas = vm.lastCallGas().gasTotalUsed;
        g.checkNotSanctioned(a, b, c, pub);
        uint256 vGas = vm.lastCallGas().gasTotalUsed;
        console.log(name);
        console.log("  publishRoot gas:", pubGas);
        console.log("  checkNotSanctioned gas (current root):", vGas);
    }

    function test_Gas_LatestOnly() public {
        _measure(new LatestOnlyGate(verifier, address(this)), "LatestOnly");
    }

    function test_Gas_RootHistory() public {
        RootHistoryGate h = new RootHistoryGate(verifier, address(this), 30);
        _measure(h, "RootHistory(N=30)");
        // 最悪ケース：受理されるルートが走査の最後（30番目のスロット）にある
        RootHistoryGate w = new RootHistoryGate(verifier, address(this), 30);
        for (uint256 k = 0; k < 29; k++) w.publishRoot(100 + k);
        w.publishRoot(root0); // スロット 29
        w.checkNotSanctioned(a, b, c, pub);
        console.log("  checkNotSanctioned gas (worst case, 30 slots scanned):", vm.lastCallGas().gasTotalUsed);
    }

    function test_Gas_TimeWindow() public {
        TimeWindowGate t = new TimeWindowGate(verifier, address(this), 1 hours);
        _measure(t, "TimeWindow(1h)");
        t.publishRoot(root1); // root0 は置き換え済み（窓の中）
        t.checkNotSanctioned(a, b, c, pub);
        console.log("  checkNotSanctioned gas (superseded root in window):", vm.lastCallGas().gasTotalUsed);
    }
}
