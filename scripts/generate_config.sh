#!/bin/bash

WG_CONF="/etc/wireguard/wg0.conf"
WG_INTERFACE="wg0"

# Генерация ключей клиента
CLIENT_PRIVKEY=$(docker exec amnezia-awg wg genkey | tr -d '\r\n')
CLIENT_PUBKEY=$(docker exec -e PRIVKEY="$CLIENT_PRIVKEY" amnezia-awg sh -c 'echo "$PRIVKEY" | wg pubkey' | tr -d '\r\n')
CLIENT_IP="10.0.0.$((2 + RANDOM % 253))"

# Добавление клиента в конфиг внутри контейнера
docker exec -i amnezia-awg sh -c "echo -e '\n[Peer]\nPublicKey = $CLIENT_PUBKEY\nAllowedIPs = $CLIENT_IP/32' >> $WG_CONF"

# Перезапуск интерфейса
docker exec amnezia-awg wg-quick down $WG_INTERFACE 2>/dev/null
docker exec amnezia-awg wg-quick up $WG_INTERFACE

# Получение серверного публичного ключа
SERVER_PUBKEY=$(docker exec amnezia-awg cat /opt/amnezia/wireguard/publickey | tr -d '\r\n')

# Формирование JSON-конфига через printf
JSON_CONFIG=$(printf '{\n  "config_version": 1.0,\n  "containers": [\n    {\n      "container": "awg",\n      "awg": {\n        "client_priv_key": "%s",\n        "client_ip": "%s",\n        "server_pub_key": "%s",\n        "server_ip": "gateway.getruchey.ru",\n        "server_port": "36016",\n        "junkPacketCount": "0",\n        "junkPacketMinSize": "0",\n        "junkPacketMaxSize": "0",\n        "initPacketJunkSize": "0",\n        "responsePacketJunkSize": "0",\n        "initPacketMagicHeader": "00000000",\n        "responsePacketMagicHeader": "00000000",\n        "underloadPacketMagicHeader": "00000000",\n        "transportPacketMagicHeader": "00000000"\n      }\n    }\n  ],\n  "defaultContainer": "awg",\n  "description": "Ruchey VPN",\n  "name": "Ruchey VPN"\n}' "$CLIENT_PRIVKEY" "$CLIENT_IP" "$SERVER_PUBKEY")

# Вывод JSON строки
echo "$JSON_CONFIG"