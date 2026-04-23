# 9. Настройка DHCP
echo "Настройка DHCP-сервера..."
apt-get install -y dhcp-server

# Генерируем секрет для TSIG ключа (чтобы не возиться с Kerberos keytab на старте)
DNS_KEY=$(samba-tool secrets get --name "dns-TEST" 2>/dev/null || echo "base64_secret_here")
# Если выше не сработало, можно просто вписать строку, но лучше так:
DNS_SECRET="Mq9X7p7Xp7Xp7Xp7Xp7Xp7==" # Это пример, в реале лучше генерить через dnssec-keygen

cat > /etc/dhcp/dhcpd.conf << EOF
# Настройки DDNS
ddns-update-style interim;
update-optimization off;
update-conflict-detection off;
allow client-updates;

# Описание ключа для авторизации в DNS Samba
# Имя ключа должно совпадать с тем, что в Samba (обычно это требует доп. настройки)
# Для упрощения часто используют метод 'allow unknown-clients' внутри subnet
key "rndc-key" {
    algorithm hmac-md5;
    secret "$DNS_SECRET";
};

zone test.alt. {
    primary 127.0.0.1;
    key "rndc-key";
}

zone 1.16.172.in-addr.arpa. {
    primary 127.0.0.1;
    key "rndc-key";
}

subnet 172.16.1.0 netmask 255.255.255.0 {
    range 172.16.1.100 172.16.1.200;
    option routers 172.16.1.1;
    option domain-name-servers 172.16.1.1;
    option domain-name "test.alt";
    
    default-lease-time 600;
    max-lease-time 7200;
    
    # Резервирование
    host workstation {
        hardware ethernet $CLIENT_MAC;
        fixed-address 172.16.1.99;
        ddns-hostname "workstation";
    }
}
EOF

# ВАЖНО для ALT Linux: указываем интерфейс
echo "DHCPDARGS=\"$INT_IF\"" > /etc/sysconfig/dhcpd

# Проверяем, есть ли IP на интерфейсе, иначе DHCP не запустится!
ip addr add 172.16.1.1/24 dev $INT_IF 2>/dev/null
ip link set $INT_IF up

systemctl enable dhcpd
systemctl restart dhcpd
