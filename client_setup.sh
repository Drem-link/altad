#!/bin/bash

ADMIN_PASS="Passw0rd123"
SERVER_IP="172.16.1.1"

echo "=== НАСТРОЙКА КЛИЕНТА ==="

# 1. КОПИРУЕМ resolv.conf с сервера (чтобы не ебаться)
echo "Копируем DNS-настройки с сервера..."
scp root@$SERVER_IP:/etc/resolv.conf /etc/resolv.conf 2>/dev/null || {
    echo "Не скопировалось — прописываем вручную"
    echo "nameserver $SERVER_IP" > /etc/resolv.conf
    echo "nameserver 8.8.8.8" >> /etc/resolv.conf
    echo "search test-alt" >> /etc/resolv.conf
}

# 2. ЗАЩИТА resolv.conf от перезаписи
chattr +i /etc/resolv.conf

# 3. СТАВИМ ПАКЕТЫ (минимум, но рабочий)
apt-get update
apt-get install -y task-auth-ad-sssd krb5-workstation realmd

# 4. KERBEROS
cat > /etc/krb5.conf << EOF
[libdefaults]
    default_realm = TEST-ALT
    dns_lookup_realm = false
    dns_lookup_kdc = true

[realms]
    TEST-ALT = {
        kdc = $SERVER_IP
        admin_server = $SERVER_IP
    }
EOF

# 5. ВВОД В ДОМЕН БЕЗ ПИЗДЕЖА
echo "Ввод в домен..."
echo "$ADMIN_PASS" | realm join --user=administrator TEST-ALT 2>/dev/null || {
    echo "realm join не сработал — пробуем net ads"
    echo "$ADMIN_PASS" | net ads join -U Administrator -S $SERVER_IP
}

# 6. РАЗРЕШАЕМ ДОМЕННЫМ ПОЛЬЗОВАТЕЛЯМ ВХОД
echo "session optional pam_mkhomedir.so skel=/etc/skel umask=0077" >> /etc/pam.d/common-session

# 7. КОНФИГ sssd (если нужно)
systemctl restart sssd

echo "=========================================="
echo "ГОТОВО. Перезагрузи: reboot"
echo "Вход: TEST\\administrator пароль $ADMIN_PASS"
echo "=========================================="
