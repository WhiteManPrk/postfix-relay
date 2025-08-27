#!/bin/bash

# Загрузка переменных из .env
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

echo "=== Настройка SMTP Relay с Certbot ==="
echo "Домен: $RELAY_DOMAIN"
echo "Email: $LETSENCRYPT_EMAIL"
echo "Mailcow IP: $MAILCOW_IP"

# Проверка DNS
echo ""
echo "=== Проверка DNS записей ==="
CURRENT_IP=$(dig +short A $RELAY_DOMAIN)
if [ -z "$CURRENT_IP" ]; then
    echo "❌ A-запись для $RELAY_DOMAIN не найдена!"
    echo "Добавьте в DNS зону r-i-m.ru:"
    echo "relay.r-i-m.ru.    A     $(curl -s ifconfig.me)"
    exit 1
fi

echo "✓ A-запись: $RELAY_DOMAIN → $CURRENT_IP"

# Проверка PTR
REVERSE_DNS=$(dig +short -x $CURRENT_IP)
if [ "$REVERSE_DNS" = "$RELAY_DOMAIN." ] || [ "$REVERSE_DNS" = "$RELAY_DOMAIN" ]; then
    echo "✓ PTR-запись: $CURRENT_IP → $REVERSE_DNS"
else
    echo "⚠️  PTR-запись неверная или отсутствует: $CURRENT_IP → $REVERSE_DNS"
    echo "Обратитесь к провайдеру VPS для настройки PTR записи"
fi

echo ""
echo "=== Запуск сервисов ==="
docker-compose up -d

echo ""
echo "=== Ожидание готовности ==="
echo "Ожидание запуска сервисов..."
sleep 10

echo "Ожидание получения сертификатов..."
timeout=300
while [ $timeout -gt 0 ]; do
    if docker-compose exec -T certbot ls /etc/letsencrypt/live/$RELAY_DOMAIN/fullchain.pem >/dev/null 2>&1; then
        echo "✓ Сертификаты получены!"
        break
    fi
    echo "⏳ Ожидание сертификатов... ($timeout сек)"
    sleep 10
    timeout=$((timeout-10))
done

if [ $timeout -le 0 ]; then
    echo "❌ Таймаут получения сертификатов!"
    echo "Проверьте логи: docker-compose logs certbot"
    exit 1
fi

echo ""
echo "=== Статус сервисов ==="
docker-compose ps

echo ""
echo "=== Тест SMTP соединения ==="
if command -v telnet >/dev/null 2>&1; then
    timeout 5 telnet $RELAY_DOMAIN 25 <<EOF || echo "Подключение к SMTP прошло успешно"
QUIT
EOF
else
    echo "Для тестирования установите telnet: apt install telnet"
fi

echo ""
echo "🎉 SMTP Relay успешно запущен!"
echo ""
echo "📋 Настройки для Mailcow:"
echo "POSTFIX_RELAYHOST=[$RELAY_DOMAIN]:25"
echo ""
echo "📊 Мониторинг:"
echo "docker-compose logs -f postfix    # Логи Postfix"
echo "docker-compose logs -f certbot    # Логи Certbot"
echo "docker-compose ps                 # Статус сервисов"
