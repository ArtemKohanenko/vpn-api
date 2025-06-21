#!/bin/bash

WG_CONF="/etc/wireguard/wg0.conf"
WG_INTERFACE="wg0"

# Генерация ключей клиента
CLIENT_PRIVKEY=$(docker exec amnezia-awg wg genkey | tr -d '\r\n')
CLIENT_PUBKEY=$(docker exec -e PRIVKEY="$CLIENT_PRIVKEY" amnezia-awg sh -c 'echo "$PRIVKEY" | wg pubkey' | tr -d '\r\n')
CLIENT_IP="10.0.0.$((2 + RANDOM % 253))"

# echo "DEBUG: CLIENT_PRIVKEY=[$CLIENT_PRIVKEY]" | cat -A
# echo "DEBUG: CLIENT_PUBKEY=[$CLIENT_PUBKEY]" | cat -A

# Добавление клиента в конфиг внутри контейнера
docker exec -i amnezia-awg sh -c "echo -e '\n[Peer]\nPublicKey = $CLIENT_PUBKEY\nAllowedIPs = $CLIENT_IP/32' >> $WG_CONF"

# Перезапуск интерфейса
docker exec amnezia-awg wg-quick down $WG_INTERFACE 2>/dev/null
docker exec amnezia-awg wg-quick up $WG_INTERFACE

# Получение серверного публичного ключа
SERVER_PUBKEY=$(docker exec amnezia-awg cat /opt/amnezia/wireguard/publickey | tr -d '\r\n')

# echo "DEBUG: SERVER_PUBKEY=[$SERVER_PUBKEY]" | cat -A

# Формирование JSON-конфига через printf
RAW_JSON=$(printf '{\n  "dns1": "8.8.8.8",\n  "dns2": "8.8.4.4",\n  "hostName": "164.90.142.218",\n  "containers": [\n    {\n      "awg": {\n        "port": "36016",\n        "transport_proto": "udp"\n      },\n      "container": "amnezia-awg"\n    }\n  ],\n  "defaultContainer": "amnezia-awg",\n  "api_config": {\n    "public_key": {\n      "expires_at": "2025-07-01 13:21:17.496318+00:00"\n    }\n  }\n}')

# Преобразование в JSON-строку (экранирование)
# JSON_STRING=$(printf '%s' "$RAW_JSON" | jq -Rs .)
JSON_STRING="$RAW_JSON"

# Кодирование в base64url
BASE64URL=$(printf '%s' "$JSON_STRING" | base64 | tr '+/' '-_' | tr -d '=\n')

# Добавление префикса и вывод
echo "vpn://$BASE64URL"
