pragma circom 2.1.6;

include "circomlib/circuits/poseidon.circom";
include "circomlib/circuits/bitify.circom";

// 葉とパス（兄弟ノード列）とインデックスのビット列からルートを計算する
template MerkleRoot(depth) {
    signal input leaf;
    signal input pathElements[depth];
    signal input indexBits[depth];   // 0 = 自分が左, 1 = 自分が右（呼び出し側でブール性を保証）
    signal output root;

    component h[depth];
    signal cur[depth + 1];
    signal left[depth];
    signal right[depth];
    cur[0] <== leaf;
    for (var i = 0; i < depth; i++) {
        // indexBits[i] = 0 のとき (cur, sib)、1 のとき (sib, cur)
        left[i]  <== cur[i] + indexBits[i] * (pathElements[i] - cur[i]);
        right[i] <== pathElements[i] + indexBits[i] * (cur[i] - pathElements[i]);
        h[i] = Poseidon(2);
        h[i].inputs[0] <== left[i];
        h[i].inputs[1] <== right[i];
        cur[i + 1] <== h[i].out;
    }
    root <== cur[depth];
}
