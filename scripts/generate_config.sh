#!/bin/bash

WG_CONF="/etc/wireguard/wg0.conf"
WG_INTERFACE="wg0"

# Генерация ключей клиента
CLIENT_PRIVKEY=$(docker exec amnezia-awg wg genkey)
CLIENT_PUBKEY=$(echo "$CLIENT_PRIVKEY" | docker exec -i amnezia-awg wg pubkey)
CLIENT_IP="10.0.0.$((2 + RANDOM % 253))"

# Добавление клиента в конфиг внутри контейнера
docker exec -i amnezia-awg sh -c "echo -e '\n[Peer]\nPublicKey = $CLIENT_PUBKEY\nAllowedIPs = $CLIENT_IP/32' >> $WG_CONF"

# Перезапуск интерфейса
docker exec amnezia-awg wg-quick down $WG_INTERFACE 2>/dev/null
docker exec amnezia-awg wg-quick up $WG_INTERFACE

# Получение серверного публичного ключа
SERVER_PUBKEY=$(docker exec amnezia-awg cat /opt/amnezia/wireguard/publickey)

# Формирование JSON-конфига
JSON_CONFIG=$(cat <<EOF
{
  "config_version": 1.0,
  "containers": [
    {
      "container": "awg",
      "awg": {
        "client_priv_key": "$CLIENT_PRIVKEY",
        "client_ip": "$CLIENT_IP",
        "server_pub_key": "$SERVER_PUBKEY",
        "server_ip": "gateway.getruchey.ru",
        "server_port": "36016",
        "junkPacketCount": "0",
        "junkPacketMinSize": "0",
        "junkPacketMaxSize": "0",
        "initPacketJunkSize": "0",
        "responsePacketJunkSize": "0",
        "initPacketMagicHeader": "00000000",
        "responsePacketMagicHeader": "00000000",
        "underloadPacketMagicHeader": "00000000",
        "transportPacketMagicHeader": "00000000"
      }
    }
  ],
  "defaultContainer": "awg",
  "description": "Ruchey VPN",
  "name": "Ruchey VPN"
}
EOF
)

# Вывод vpn:// ссылки
VPN_URI="vpn://$(echo "$JSON_CONFIG" | base64 -w 0)"
echo "🔗 Ссылка для импорта:"
echo "$VPN_URI"
