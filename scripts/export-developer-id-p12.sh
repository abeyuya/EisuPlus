#!/bin/zsh
# Developer ID Application の証明書と秘密鍵だけを .p12 にして、base64 とパスワードを順にクリップボードへ入れる
set -euo pipefail
keychain="${1:-$HOME/Library/Keychains/login.keychain-db}"
name="${2:-Developer ID Application: YUYA ABE (37XL3EDJ44)}"
umask 077
d="$(mktemp -d)"; trap 'rm -rf "$d"' EXIT
export P1="$(uuidgen)" P2="$(uuidgen)"
security find-certificate -c "$name" -p "$keychain" > "$d/cert.pem"
security export -k "$keychain" -t identities -f pkcs12 -P "$P1" -o "$d/all.p12"
openssl pkcs12 -legacy -in "$d/all.p12" -passin env:P1 -nocerts -nodes 2>/dev/null \
  | LC_ALL=C awk -v d="$d" '/BEGIN PRIVATE KEY/{n++; f=d"/key" n ".pem"} f{print > f} /END PRIVATE KEY/{f=""}'
want="$(openssl x509 -in "$d/cert.pem" -noout -pubkey)"
key=""
for k in "$d"/key*.pem; do
  [[ "$(openssl pkey -in "$k" -pubout)" == "$want" ]] && key="$k" && break
done
[[ -n "$key" ]] || { echo "error: $name の秘密鍵が見つからない" >&2; exit 1; }
openssl pkcs12 -export -inkey "$key" -in "$d/cert.pem" -name "$name" -passout env:P2 \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 -out "$d/devid.p12"
base64 -i "$d/devid.p12" | tr -d '\n' | pbcopy
echo "DEVELOPER_ID_P12_BASE64 をクリップボードに入れた。Xcode Cloud に貼ったら Enter"
read -r
print -rn -- "$P2" | pbcopy
echo "DEVELOPER_ID_P12_PASSWORD をクリップボードに入れた。貼ったら Enter でクリップボードを消す"
read -r
print -n "" | pbcopy
echo "done"
