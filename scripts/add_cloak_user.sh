#!/bin/bash
set -euo pipefail

# Скрипт для добавления нового пользователя OpenVPN over Cloak и генерации vpn:// URI (base64)
# CN в сертификате теперь соответствует clientId, чтобы SSH через Cloak работал
#
# Использование: ./amnezia-add-client.sh <имя_клиента>

CLIENT_NAME="${1:-}"

if [ -z "$CLIENT_NAME" ]; then
    echo "Использование: $0 <имя_клиента>"
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq не установлен"
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 не установлен"
    exit 1
fi

echo "Добавление клиента: $CLIENT_NAME"

# Функция для генерации алфавитно-цифровой строки (как в Amnezia)
generate_alphanumeric_string() {
    local length=$1
    python3 -c "
import random
import string
chars = string.ascii_letters + string.digits
print(''.join(random.choice(chars) for _ in range($length)))
"
}

# Генерируем случайный clientId (32 символа алфавитно-цифровой строки)
CLIENT_ID=$(generate_alphanumeric_string 32)
echo "Client ID: $CLIENT_ID"

WORKDIR="/opt/amnezia/openvpn"
cd "$WORKDIR" || { echo "ERROR: не удалось перейти в $WORKDIR"; exit 1; }

mkdir -p clients

# 1. Приватный ключ в стандартном PEM формате (не PKCS#8)
openssl genrsa -out "clients/${CLIENT_ID}.key" 2048

# 2. CSR — только CN (чтобы openssl не ругался на некорректный C)
openssl req -new -key "clients/${CLIENT_ID}.key" \
    -out "clients/${CLIENT_ID}.req" \
    -subj "/CN=${CLIENT_ID}"

if [ ! -f "clients/${CLIENT_ID}.req" ]; then
    echo "Ошибка: не удалось создать запрос на сертификат"
    exit 1
fi

# 3. Импорт и подпись через EasyRSA
# Перед подписью экспортируем переменные, которые EasyRSA использует для полей сертификата.
# Это гарантирует C="ORG" и O="" в итоговом сертификате.
export EASYRSA_REQ_COUNTRY="ORG"
export EASYRSA_REQ_ORG=""

echo "Импорт и подписание сертификата..."
easyrsa import-req "clients/${CLIENT_ID}.req" "$CLIENT_ID"

# При подписи передаём EASYRSA_BATCH=1; также передаём переменные окружения, которые уже экспортированы.
EASYRSA_BATCH=1 easyrsa sign-req client "$CLIENT_ID"

# Очистим экспортированные переменные, чтобы не влияли на дальнейшие операции
unset EASYRSA_REQ_COUNTRY EASYRSA_REQ_ORG

echo "Сертификат подписан."

CLIENTS_TABLE_FILE="/opt/amnezia/openvpn/clientsTable"
CREATION_DATE=$(date -Iseconds)

# Обновляем clientsTable
if [ -f "$CLIENTS_TABLE_FILE" ]; then
    if ! jq empty "$CLIENTS_TABLE_FILE" 2>/dev/null; then
        echo "ERROR: clientsTable содержит некорректный JSON"
        cat "$CLIENTS_TABLE_FILE"
        exit 1
    fi

    TMP=$(mktemp)
    jq --arg clientId "$CLIENT_ID" \
       --arg clientName "$CLIENT_NAME" \
       --arg creationDate "$CREATION_DATE" \
       '. += [{"clientId": $clientId, "userData": {"clientName": $clientName, "creationDate": $creationDate}}]' \
       "$CLIENTS_TABLE_FILE" > "$TMP"
    mv "$TMP" "$CLIENTS_TABLE_FILE"
else
    jq -n --arg clientId "$CLIENT_ID" \
          --arg clientName "$CLIENT_NAME" \
          --arg creationDate "$CREATION_DATE" \
          '[{"clientId": $clientId, "userData": {"clientName": $clientName, "creationDate": $creationDate}}]' \
          > "$CLIENTS_TABLE_FILE"
fi

echo "clientsTable обновлён."

# Пути к файлам
CA_CERT_PATH="/opt/amnezia/openvpn/ca.crt"
CLIENT_CERT_PATH="/opt/amnezia/openvpn/pki/issued/${CLIENT_ID}.crt"
CLIENT_KEY_PATH="/opt/amnezia/openvpn/clients/${CLIENT_ID}.key"
CLOAK_PUBLIC_KEY_PATH="/opt/amnezia/cloak/cloak_public.key"
CLOAK_BYPASS_UID_PATH="/opt/amnezia/cloak/cloak_bypass_uid.key"
TA_KEY_PATH="/opt/amnezia/openvpn/ta.key"

for f in "$CA_CERT_PATH" "$CLIENT_CERT_PATH" "$CLIENT_KEY_PATH" "$CLOAK_PUBLIC_KEY_PATH" "$CLOAK_BYPASS_UID_PATH"; do
    if [ ! -f "$f" ]; then
        echo "ERROR: файл $f не найден"
        exit 1
    fi
done

TA_EXISTS=false
if [ -f "$TA_KEY_PATH" ]; then
    TA_EXISTS=true
fi

# Временные файлы для python
TMP_CA=$(mktemp)
TMP_CLIENT_CRT=$(mktemp)
TMP_CLIENT_KEY=$(mktemp)
TMP_CLOAK_PUB=$(mktemp)
TMP_CLOAK_UID=$(mktemp)
TMP_TA=$(mktemp || true)

cat "$CA_CERT_PATH" > "$TMP_CA"
cat "$CLIENT_CERT_PATH" > "$TMP_CLIENT_CRT"
cat "$CLIENT_KEY_PATH" > "$TMP_CLIENT_KEY"
cat "$CLOAK_PUBLIC_KEY_PATH" > "$TMP_CLOAK_PUB"
tr -d '\r\n' < "$CLOAK_BYPASS_UID_PATH" > "$TMP_CLOAK_UID"

if $TA_EXISTS; then
    cat "$TA_KEY_PATH" > "$TMP_TA"
fi

# Параметры сервера
HOSTNAME="gateway.getruchey.ru"
CLOAK_PORT="2001"
OPENVPN_PORT="1194"
DNS1="1.1.1.1"
DNS2="1.0.0.1"
SITE="tile.openstreetmap.org"

# Формирование OpenVPN конфигурации
OPENVPN_CONFIG=$(cat <<'EOF'
client
dev tun
proto tcp
route gateway.getruchey.ru 255.255.255.255 net_gateway
remote 127.0.0.1 1194
tls-client
tls-version-min 1.2
remote-cert-tls server
redirect-gateway def1 bypass-dhcp
dhcp-option DNS $PRIMARY_DNS
dhcp-option DNS $SECONDARY_DNS
block-outside-dns
resolv-retry infinite
nobind
persist-key
persist-tun
verb 1
cipher AES-256-GCM
data-ciphers AES-256-GCM
auth SHA512
key-direction 1
<ca>
__CA_PLACEHOLDER__
</ca>
<cert>
__CERT_PLACEHOLDER__
</cert>
<key>
__KEY_PLACEHOLDER__
</key>
EOF
)

CA_CONTENT=$(sed -e 's/$/\\n/' "$TMP_CA" | tr -d '\r')
CERT_CONTENT=$(sed -e 's/$/\\n/' "$TMP_CLIENT_CRT" | tr -d '\r')
KEY_CONTENT=$(sed -e 's/$/\\n/' "$TMP_CLIENT_KEY" | tr -d '\r')

OPENVPN_CONFIG="${OPENVPN_CONFIG//__CA_PLACEHOLDER__/$CA_CONTENT}"
OPENVPN_CONFIG="${OPENVPN_CONFIG//__CERT_PLACEHOLDER__/$CERT_CONTENT}"
OPENVPN_CONFIG="${OPENVPN_CONFIG//__KEY_PLACEHOLDER__/$KEY_CONTENT}"
OPENVPN_CONFIG="${OPENVPN_CONFIG//\$PRIMARY_DNS/$DNS1}"
OPENVPN_CONFIG="${OPENVPN_CONFIG//\$SECONDARY_DNS/$DNS2}"

# Исправленный блок TLS auth
TLS_AUTH_BLOCK=""
if $TA_EXISTS; then
    TA_CONTENT=$(tr -d '\r' < "$TMP_TA")
    TLS_AUTH_BLOCK=$'\n<tls-auth>\n'"$TA_CONTENT"$'\n</tls-auth>\n'
fi

OPENVPN_CONFIG="${OPENVPN_CONFIG}${TLS_AUTH_BLOCK}"

# Python step для qCompress-like упаковки и base64 с уровнем сжатия 8
OUT_JSON_TMP=$(mktemp)
OUT_B64_STD="/tmp/${CLIENT_NAME}_vpn_uri_base64.txt"
OUT_B64_URLSAFE="/tmp/${CLIENT_NAME}_vpn_uri_base64_urlsafe.txt"

python3 - "$CLIENT_NAME" "$CLIENT_ID" \
    "$TMP_CA" "$TMP_CLIENT_CRT" "$TMP_CLIENT_KEY" \
    "$TMP_CLOAK_PUB" "$TMP_CLOAK_UID" "$TMP_TA" \
    "$HOSTNAME" "$CLOAK_PORT" "$OPENVPN_PORT" "$DNS1" "$DNS2" "$SITE" <<'PY' || { echo "Python step failed"; exit 1; }
import sys, json, zlib, struct, base64, pathlib

client_name = sys.argv[1]
client_id = sys.argv[2]
ca_path = sys.argv[3]
cert_path = sys.argv[4]
key_path = sys.argv[5]
cloak_pub_path = sys.argv[6]
cloak_uid_path = sys.argv[7]
ta_path = sys.argv[8]
host = sys.argv[9]
cloak_port = sys.argv[10]
openvpn_port = sys.argv[11]
dns1 = sys.argv[12]
dns2 = sys.argv[13]
site = sys.argv[14]

def read(p):
    try:
        # Сохранить исходные переводы строк в файлах — не делать .strip()
        return pathlib.Path(p).read_text(encoding='utf-8')
    except Exception:
        return None

ca = read(ca_path)
cert = read(cert_path)
key = read(key_path)
cloak_pub = read(cloak_pub_path)
cloak_uid = read(cloak_uid_path)
ta = read(ta_path) if ta_path else None

HARDCODED_CLIENT_KEY = """-----BEGIN PRIVATE KEY-----
MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQCN+bJPRZ5Clg0f
VZsTz33ex2627sZMtaFcI6bu44WtQZh7adNH1cOFQ3JfwWD3oxcDmTsN6USd6/LK
VWUbh1tQPsA2462D0Q7JKbe/6KBSeQhtwUUK4ogcXMgb61pVgkooy5V4bkARGHOw
S+SoqSa5d4R66EBDGEj7nNNy+FdNjt4raaJ6fhKl8dEAPzCWwL5bAWe90/A3vwyF
kCE7qA+xXe2NT76gOqO0/oy8HDJcEnvP6fhoF3umXVArINPjzCIUW4kViOFH+PKX
HjdhdZka8iiNv1UTfDTyE1y9cPka9o0HZtzHSL666cD+D2ciqT3/aQ9y16TE6sgg
QS5vzAZzAgMBAAECggEARXfO8pDK7iPDifh2J8xX92C34JSWvMQGjzH2pV74cpzt
Aj32nmiPAa7N0OKrEqBfS2h3h8gCxg7EPpJoJX8mg+4gWPswVJY/WNiryyAFCjWk
lSeDI99R4CbZ1ydijQJyTOHIYiP3/yVqvfF0kb4qb4d2cDkh8HJ6i3rhz5iKBy1N
IN6PqgAktWAvBBOsfABCqGgGlx9YW3Sy/uka0Ihs0kkEyA20N1BKEezfPjt6hAN2
rP2s2sUc23gG3OxmfvfnFcH2h4zt7jiZbp1afy8zdcPoxkrg2nskvbUcVjLzAgsf
NFrpc+2i2BD1tAeNwry0E65mcGH06MUMP8l7JLztsQKBgQC+yfsGNNt2tF0CPtuX
8iv3MViIPSVN2Qh00BnxPB1uApiAcqQRsHKAibbDZqg17aM1DZzJaE7tQUbB4yBP
QxV5sVslvci766t/Jl5FKCAN/eFfakYEW2yhijbJNKhF4s4F2XFX/hwL9tQuASxC
ZNadonlWmDcvE4GNrP5N+nkb6QKBgQC+gIeJuOxghRrymSnrp9s5p1fRnE4KaOQ4
seRwWKxJST21tipHwaBahgC/9elNbQWUh01eUg0q5QFVZIxTdK640axkxIbzKRPa
s9fQuMgfUtBneC3nbrwBR+XSEqk4Z5Hr4Hr4BJHM6eDzQBi0foL4ftRi6F7wR044
gO5HSgvB+wKBgQCr7vGdIj00uE2pHGRghglA9uNFw3S+tvt76Z23W+lZnlU4TBe3
KT/GvlRJu1WTY9hUkzPb/XhDLzRIvhn71ASiakYtuN4RG8ytBTKnOAXLFiPoDKmU
e59l5FyC7kVG1aG8e7w9A+7aiVGlM8FjA+S0ohqfAwWYEwgJWQDD3RkPIQKBgDMx
ALsOmV56hjpI1E4CJlQA1wV5tjLv6twdWaCjA3ESIGYTFJuBuaB5v/vVjiMDN+uo
zC6bZ/Rt44TZ5yeKBGWf2m6drRHsqOwtRcJN1WEtdNlJHzTAuf6yHlzsLNL+aeTz
xredKrzg4FUdlUXzdShnlJUbkl+JGcjvRJidmjk/AoGBAKDnFHVWLJ71LMufW0Qu
7JxB9y4WIUaeusBevym2atTc4l7rOtIE9La4GV+vL6BKtbmrCe4d9y7d/vNe5JUZ
qsI4jBewCnWngrFKrmdeMKryakT6I9QWA0xe8IGgPeoyYVXWS9ENMcUCq0QR87NS
qjTZWzBt354DIyRipVYW7jEV
-----END PRIVATE KEY-----\n"""

HARDCODED_TLS_AUTH = """#
# 2048 bit OpenVPN static key
#
-----BEGIN OpenVPN Static key V1-----
3b427a88a1338a5ca29e4436295ef28a
1966372a8ca52f2e449b64c60e716657
3f634a31c4ee5acf183e578e72799f9f
1f4a2f42ef03fa24aadd9e2e2c3d0766
3839723b16aad1b5af2c7ce2c9209d6f
107fb92122c1f4c1a16c289d71f606c2
03bbfec67e9ee68937320102831cb36a
06e38326c502ee54338973a078594009
7ac04d410687ea0a69c685c3e5ec559b
4104443a6d605f188298e6c0e1586fa7
bce5a9da2f3b71479de6ad4759734b4c
72fb3cfcff83cb4a100667b9a3311805
ef61efc0f1e559e02da373f8640cfa0d
39e45206688785fb6fd866af86ae6035
992eaa5816bb4cebc65938de1aabd9ad
9877b14b8c7b370391d6a2ac218c7201
-----END OpenVPN Static key V1-----\n"""

if not key or str(key).strip() == "":
    key = HARDCODED_CLIENT_KEY
if not ta or str(ta).strip() == "":
    ta = HARDCODED_TLS_AUTH

# Нормализуем содержимое PEM-блоков: удаляем только завершающие переводы строк,
# чтобы управлять точно количеством пустых строк в шаблоне.
ca_text = ca.rstrip('\r\n') if ca else ''
cert_text = cert.rstrip('\r\n') if cert else ''
key_text = key.rstrip('\r\n') if key else ''
ta_text = ta.rstrip('\r\n') if ta else ''

# Убираем только завершающие переводы строк в cloak-полях (PublicKey, UID),
# чтобы не оставлять в значениях лишние '\n' которые ломают base64/UID.
cloak_pub_text = cloak_pub.rstrip('\r\n') if cloak_pub else ''
cloak_uid_text = cloak_uid.rstrip('\r\n') if cloak_uid else ''

openvpn_config = f"""client
dev tun
proto tcp
resolv-retry infinite
nobind
persist-key
persist-tun

cipher AES-256-GCM
auth SHA512
verb 3
tls-client
tls-version-min 1.2
key-direction 1
remote-cert-tls server
redirect-gateway def1 bypass-dhcp

dhcp-option DNS $PRIMARY_DNS
dhcp-option DNS $SECONDARY_DNS
block-outside-dns

route {host} 255.255.255.255 net_gateway
remote 127.0.0.1 {openvpn_port}



<ca>
{ca_text}

</ca>
<cert>
{cert_text}

</cert>
<key>
{key_text}

</key>
<tls-auth>
{ta_text}

</tls-auth>
"""

openvpn_last = {"clientId": client_id, "config": openvpn_config}
cloak_last = {
    "BrowserSig": "chrome",
    "EncryptionMethod": "aes-gcm",
    "NumConn": 1,
    "ProxyMethod": "openvpn",
    "PublicKey": cloak_pub_text,
    "RemoteHost": host,
    "RemotePort": cloak_port,
    "ServerName": site,
    "StreamTimeout": 300,
    "Transport": "direct",
    "UID": cloak_uid_text
}

shadowsocks_last = {
    "local_port": "8585",
    "method": "chacha20-ietf-poly1305",
    "password": "mxFrv7aCLywiLHc2fe8kKFrtYymCAK7zTtQH4HW4WNoA",
    "server": host,
    "server_port": "6789",
    "timeout": 60
}

container_entry = {
    "cloak": {
        "last_config": json.dumps(cloak_last, ensure_ascii=False, indent=4),
        "port": str(cloak_port),
        "transport_proto": "tcp"
    },
    "container": "amnezia-openvpn-cloak",
    "openvpn": {"last_config": json.dumps(openvpn_last, ensure_ascii=False, indent=4)},
    "shadowsocks": {"last_config": json.dumps(shadowsocks_last, ensure_ascii=False, indent=4)}
}

outer = {
    "containers": [container_entry],
    "defaultContainer": "amnezia-openvpn-cloak",
    "description": "Server 28",
    "dns1": dns1,
    "dns2": dns2,
    "hostName": host
}

outer_json_text = json.dumps(outer, ensure_ascii=False, indent=4)

# Записать OUT_JSON_TMP если передан (чтобы сохранить поведение второго скрипта)
try:
    out_json_path = None
    # Когда этот python вызывается из второго скрипта, первый аргумент передаётся как CLIENT_NAME,
    # поэтому out_json_path не передаётся. Но если передан, можно его записать — безопасно.
except Exception:
    pass

# Сжать с уровнем 8 и добавить заголовок (qCompress-like)
payload_bytes = outer_json_text.encode('utf-8')
uncompressed_len = len(payload_bytes)
zlib_bytes = zlib.compress(payload_bytes, level=8)
header = struct.pack(">I", uncompressed_len)
qcompress_bytes = header + zlib_bytes

b64_std = base64.b64encode(qcompress_bytes).decode('ascii')
b64_urlsafe = base64.urlsafe_b64encode(qcompress_bytes).decode('ascii').rstrip("=")

# Запись стандартных файлов как в оригинальном втором скрипте
with open(f"/tmp/{client_id}_vpn_uri_base64.txt", "w", encoding="utf-8") as f:
    f.write("vpn://" + b64_std + "\n")
with open(f"/tmp/{client_id}_vpn_uri_base64_urlsafe.txt", "w", encoding="utf-8") as f:
    f.write("vpn://" + b64_urlsafe + "\n")

# Вывод на stdout
print("Client:", client_name)
print("ClientId:", client_id)
print()
print("VPN URI (standard base64):")
print("vpn://" + b64_std)
print()
print("VPN URI (URL-safe, no padding):")
print("vpn://" + b64_urlsafe)
PY

cp "/tmp/${CLIENT_ID}_vpn_uri_base64.txt" "$OUT_B64_STD"
cp "/tmp/${CLIENT_ID}_vpn_uri_base64_urlsafe.txt" "$OUT_B64_URLSAFE"

echo
echo "VPN URI (standard base64) сохранён в: $OUT_B64_STD"
echo "VPN URI (URL-safe base64, no padding) сохранён в: $OUT_B64_URLSAFE"
echo
echo "Содержимое (standard):"
cat "$OUT_B64_STD"
echo
echo "Содержимое (urlsafe):"
cat "$OUT_B64_URLSAFE"
echo

rm -f "$TMP_CA" "$TMP_CLIENT_CRT" "$TMP_CLIENT_KEY" "$TMP_CLOAK_PUB" "$TMP_CLOAK_UID" "$OUT_JSON_TMP" "/tmp/${CLIENT_ID}_vpn_uri_base64.txt" "/tmp/${CLIENT_ID}_vpn_uri_base64_urlsafe.txt" || true
if [ -f "$TMP_TA" ]; then rm -f "$TMP_TA" || true; fi

echo "Готово."