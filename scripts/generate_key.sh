#!/bin/bash

# Параметры API (замените на свои реальные значения)
API_ENDPOINT="http://gateway.getruchey.ru:8080/api/v1/request/awg/"
API_KEY="4uHZMaJH.9lF0xRsLJSs6zyVUHX7zdbN9kjJmchix"
VPN_NAME="Ruchey"
VPN_DESCRIPTION="Its Ruchey time!!"

# Генерация ключей клиента
CLIENT_PRIVKEY=$(docker exec amnezia-awg wg genkey)
CLIENT_PUBKEY=$(echo "$CLIENT_PRIVKEY" | docker exec -i amnezia-awg wg pubkey)
CLIENT_IP="10.0.0.$((2 + RANDOM % 253))"

# Добавление клиента в конфиг внутри контейнера
WG_CONF="/etc/wireguard/wg0.conf"
WG_INTERFACE="wg0"
docker exec -i amnezia-awg sh -c "echo -e '\n[Peer]\nPublicKey = $CLIENT_PUBKEY\nAllowedIPs = $CLIENT_IP/32' >> $WG_CONF"

# Перезапуск интерфейса
docker exec amnezia-awg wg-quick down $WG_INTERFACE 2>/dev/null
docker exec amnezia-awg wg-quick up $WG_INTERFACE

# Формирование JSON-конфига в новом формате
JSON_CONFIG=$(cat <<EOF
{
  "config_version": 1.0,
  "api_endpoint": "$API_ENDPOINT",
  "protocol": "awg",
  "name": "$VPN_NAME",
  "description": "$VPN_DESCRIPTION",
  "api_key": "$API_KEY"
}
EOF
)

# Вывод vpn:// ссылки
VPN_URI="vpn://$(echo "$JSON_CONFIG" | base64 -w 0)"
echo "🔗 Ссылка для импорта:"
echo "$VPN_URI"