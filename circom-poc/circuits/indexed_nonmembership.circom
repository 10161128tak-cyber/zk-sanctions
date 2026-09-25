pragma circom 2.1.6;

include "circomlib/circuits/poseidon.circom";
include "circomlib/circuits/comparators.circom";
include "circomlib/circuits/bitify.circom";
include "./merkle.circom";

// 【方式B】Indexed Merkle tree（Aztec方式）による非掲載証明
// 葉 = Poseidon(value, nextValue)。各葉が「次に大きい値」を持つので、
// low < x < nextValue を満たす葉が1枚あれば非掲載を示せる（パスは1本で済む）。
template IndexedNonMembership(depth) {
    signal input root;             // public
    signal input addrCommitment;   // public

    signal input x;
    signal input blinding;
    signal input lowValue;
    signal input lowNext;
    signal input lowIndex;
    signal input lowPath[depth];

    component c = Poseidon(2);
    c.inputs[0] <== x;
    c.inputs[1] <== blinding;
    c.out === addrCommitment;

    component rx = Num2Bits(252); rx.in <== x;
    component rl = Num2Bits(252); rl.in <== lowValue;
    component rn = Num2Bits(252); rn.in <== lowNext;

    component lt1 = LessThan(252); lt1.in[0] <== lowValue; lt1.in[1] <== x;       lt1.out === 1;
    component lt2 = LessThan(252); lt2.in[0] <== x;        lt2.in[1] <== lowNext; lt2.out === 1;

    component bl = Num2Bits(depth); bl.in <== lowIndex;
    component hl = Poseidon(2); hl.inputs[0] <== lowValue; hl.inputs[1] <== lowNext;

    component ml = MerkleRoot(depth);
    ml.leaf <== hl.out;
    for (var i = 0; i < depth; i++) { ml.pathElements[i] <== lowPath[i]; ml.indexBits[i] <== bl.out[i]; }
    ml.root === root;
}

component main {public [root, addrCommitment]} = IndexedNonMembership(DEPTH);
