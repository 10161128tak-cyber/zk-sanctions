# OFAC SDN のデジタル通貨アドレスの更新履歴を集計する
# 使い方: git clone https://github.com/0xB10C/ofac-sanctioned-digital-currency-addresses ofac
#         cd ofac && git checkout lists && python3 ofac_crypto_updates.py > ofac_crypto_updates.csv
# lists ブランチは毎日 SDN リストを取得し、アドレスに変化があった日だけコミットする。
# 毎日の取得が始まった 2022-09-15 以降を対象にする。
import subprocess

EVM = ["ETH", "USDT", "USDC", "ARB", "BSC"]
log = subprocess.check_output(["git", "log", "--reverse", "--format=%H %ad", "--date=short"]).decode().split("\n")
print("date,added,removed,added_evm")
for line in filter(None, log):
    h, d = line.split()
    if d < "2022-09-15":
        continue
    add = rem = evm = 0
    for l in subprocess.check_output(["git", "show", "--numstat", "--format=", h]).decode().splitlines():
        a, r, f = l.split("\t")
        if not f.endswith(".txt"):
            continue
        add += int(a); rem += int(r)
        if any(f.endswith(f"_{c}.txt") for c in EVM):
            evm += int(a)
    print(f"{d},{add},{rem},{evm}")
