pragma circom 2.1.6;

include "circomlib/circuits/poseidon.circom";
include "circomlib/circuits/comparators.circom";
include "circomlib/circuits/bitify.circom";
include "./merkle.circom";

// 【方式A】Sorted Merkle tree による非掲載証明
// 葉 = Poseidon(value)。リストは昇順に並べ、両端に番兵 0 と 2^252-1 を置く。
// x が掲載されていない ⇔ 隣り合う2つの葉 low (index i), high (index i+1) が存在して low < x < high。
// 公開入力: root（リストのルート）, addrCommitment = Poseidon(x, blinding)
template SortedNonMembership(depth) {
    signal input root;             // public
    signal input addrCommitment;   // public

    signal input x;                // 秘密: 利用者のアドレス
    signal input blinding;         // 秘密: コミットメントの乱数
    signal input low;
    signal input high;
    signal input lowIndex;
    signal input lowPath[depth];
    signal input highPath[depth];

    // x をコミットメントに結びつける（証明と取引を紐付ける役）
    component c = Poseidon(2);
    c.inputs[0] <== x;
    c.inputs[1] <== blinding;
    c.out === addrCommitment;

    // 比較を健全にするため 252 ビット以内に制限
    component rx = Num2Bits(252); rx.in <== x;
    component rl = Num2Bits(252); rl.in <== low;
    component rh = Num2Bits(252); rh.in <== high;

    // low < x < high
    component lt1 = LessThan(252); lt1.in[0] <== low; lt1.in[1] <== x;    lt1.out === 1;
    component lt2 = LessThan(252); lt2.in[0] <== x;   lt2.in[1] <== high; lt2.out === 1;

    // 隣接性: high の位置 = low の位置 + 1（Num2Bits が桁あふれも防ぐ）
    component bl = Num2Bits(depth); bl.in <== lowIndex;
    component bh = Num2Bits(depth); bh.in <== lowIndex + 1;

    component hl = Poseidon(1); hl.inputs[0] <== low;
    component hh = Poseidon(1); hh.inputs[0] <== high;

    component ml = MerkleRoot(depth);
    ml.leaf <== hl.out;
    for (var i = 0; i < depth; i++) { ml.pathElements[i] <== lowPath[i]; ml.indexBits[i] <== bl.out[i]; }
    component mh = MerkleRoot(depth);
    mh.leaf <== hh.out;
    for (var i = 0; i < depth; i++) { mh.pathElements[i] <== highPath[i]; mh.indexBits[i] <== bh.out[i]; }

    ml.root === root;
    mh.root === root;
}

component main {public [root, addrCommitment]} = SortedNonMembership(DEPTH);
