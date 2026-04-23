#!/bin/bash

ADMIN_PASS="Passw0rd123"
SERVER_IP="172.16.1.1"

echo "=== НАСТРОЙКА КЛИЕНТА ==="

# 1. DNS
echo "Настройка DNS..."
cat > /etc/resolv.conf << EOF
nameserver $SERVER_IP
nameserver 8.8.8.8
search test-alt
EOF

# 2. Пакеты
echo "Установка пакетов..."
apt-get update
apt-get install -y task-auth-ad-sssd krb5-workstation realmd samba-client

# 3. Kerberos с явным указанием KDC (чтобы точно видел)
echo "Настройка Kerberos..."
cat > /etc/krb5.conf << EOF
[libdefaults]
    default_realm = TEST-ALT
    dns_lookup_realm = false
    dns_lookup_kdc = false
    ticket_lifetime = 24h
    renew_lifetime = 7d

[realms]
    TEST-ALT = {
        kdc = $SERVER_IP
        admin_server = $SERVER_IP
    }

[domain_realm]
    .test-alt = TEST-ALT
    test-alt = TEST-ALT
EOF

# 4. Проверка Kerberos
echo "Проверка Kerberos..."
echo "$ADMIN_PASS" | kinit administrator@TEST-ALT 2>/dev/null
if klist 2>/dev/null | grep -q "Ticket cache"; then
    echo "✅ Kerberos работает"
else
    echo "❌ Kerberos не работает, проверь подключение к серверу"
    echo "Попробуй вручную: kinit administrator@TEST-ALT"
fi

# 5. SSSD (заготовка)
mkdir -p /etc/sssd

echo "=========================================="
echo "✅ ПАКЕТЫ УСТАНОВЛЕНЫ, DNS НАСТРОЕН"
echo ""
echo "ТЕПЕРЬ ВРУЧНУЮ (через графику):"
echo "1. Запусти: alterator (или acc)"
echo "2. Выбери: Пользователи → Аутентификация"
echo "3. Выбери: Active Directory or ALT Domain"
echo "4. Введи:"
echo "   Домен: TEST-ALT"
echo "   Контроллер: $SERVER_IP"
echo "   Пользователь: administrator"
echo "   Пароль: $ADMIN_PASS"
echo "5. Нажми Применить и перезагрузись"
echo ""
echo "Если не работает через графику — введи вручную:"
echo "   realm join --user=administrator TEST-ALT"
echo ""
echo "После перезагрузки войди как: TEST\\administrator"
echo "Пароль: $ADMIN_PASS"
echo "=========================================="
