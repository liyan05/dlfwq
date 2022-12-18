#!/bin/sh
# forum: https://1024.day

if [[ $EUID -ne 0 ]]; then
    clear
    echo "Error: This script must be run as root!" 1>&2
    exit 1
fi

timedatectl set-timezone Asia/Shanghai
v2path=$(cat /dev/urandom | head -1 | md5sum | head -c 6)
v2uuid=$(cat /proc/sys/kernel/random/uuid)

install_precheck(){
    echo "====�����Ѿ�DNS�����õ�����===="
    read domain
    
    if [ -f "/usr/bin/apt-get" ]; then
        apt-get update -y
        apt-get install -y net-tools curl
    else
        yum update -y
        yum install -y epel-release
        yum install -y net-tools curl
    fi

    sleep 3
    isPort=`netstat -ntlp| grep -E ':80 |:443 '`
    if [ "$isPort" != "" ];then
        clear
        echo " ================================================== "
        echo " 80��443�˿ڱ�ռ�ã������ͷŶ˿������д˽ű�"
        echo
        echo " �˿�ռ����Ϣ���£�"
        echo $isPort
        echo " ================================================== "
        exit 1
    fi
}

install_nginx(){
    if [ -f "/usr/bin/apt-get" ];then
        apt-get install -y nginx
    else
        yum install -y nginx
    fi

cat >/etc/nginx/nginx.conf<<EOF
pid /var/run/nginx.pid;
worker_processes auto;
worker_rlimit_nofile 51200;
events {
    worker_connections 1024;
    multi_accept on;
    use epoll;
}
http {
    server_tokens off;
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 120s;
    keepalive_requests 10000;
    types_hash_max_size 2048;
    include /etc/nginx/mime.types;
    access_log off;
    error_log /dev/null;
    server {
        listen 80;
        listen [::]:80;
        server_name $domain;
        location / {
            return 301 https://\$server_name\$request_uri;
        }
    }
    server {
        listen 443 ssl http2;
        listen [::]:443 ssl http2;
        server_name $domain;
        ssl_protocols TLSv1.1 TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:HIGH:!aNULL:!MD5:!RC4:!DHE;
        ssl_prefer_server_ciphers on;
        ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;        
        location / {
            default_type text/plain;
            return 200 "Hello World !";
        }        
        location /$v2path {
            proxy_redirect off;
            proxy_pass http://127.0.0.1:8080;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host \$http_host;
        }
    }
}
EOF
}

acme_ssl(){    
    apt-get -y install cron socat || yum -y install cronie socat
    curl https://get.acme.sh | sh -s email=my@example.com
    mkdir -p /etc/letsencrypt/live/$domain
    ~/.acme.sh/acme.sh --issue -d $domain --standalone --keylength ec-256 --pre-hook "systemctl stop nginx" --post-hook "~/.acme.sh/acme.sh --installcert -d $domain --ecc --fullchain-file /etc/letsencrypt/live/$domain/fullchain.pem --key-file /etc/letsencrypt/live/$domain/privkey.pem --reloadcmd \"systemctl restart nginx\""
}

install_v2ray(){    
    bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh) --version v4.45.2
    
cat >/usr/local/etc/v2ray/config.json<<EOF
{
  "inbounds": [
    {
      "port": 8080,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "$v2uuid"
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
        "path": "/$v2path"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF

    systemctl enable v2ray.service && systemctl restart v2ray.service
    rm -f tcp-wss.sh install-release.sh

cat >/usr/local/etc/v2ray/client.json<<EOF
{
===========���ò���=============
��ַ��${domain}
�˿ڣ�443/8080
UUID��${v2uuid}
���ܷ�ʽ��aes-128-gcm
����Э�飺ws
·����/${v2path}
�ײ㴫�䣺tls
ע�⣺8080�������˿ڲ���Ҫ��tls
}
EOF

    clear
}

install_sslibev(){
    if [ -f "/usr/bin/apt-get" ];then
        apt-get update -y
        apt-get install -y --no-install-recommends \
            autoconf automake debhelper pkg-config asciidoc xmlto libpcre3-dev apg pwgen rng-tools \
            libev-dev libc-ares-dev dh-autoreconf libsodium-dev libmbedtls-dev git
    else
        yum update -y
        yum install epel-release -y
        yum install gcc gettext autoconf libtool automake make pcre-devel asciidoc xmlto c-ares-devel libev-devel libsodium-devel mbedtls-devel git -y  
    fi

    git clone https://github.com/shadowsocks/shadowsocks-libev.git
    cd shadowsocks-libev
    git submodule update --init --recursive
    ./autogen.sh && ./configure --prefix=/usr && make
    make install
    mkdir -p /etc/shadowsocks-libev

cat >/etc/shadowsocks-libev/config.json<<EOF
{
    "server":["[::0]","0.0.0.0"],
    "server_port":10240,
    "password":"$v2uuid",
    "timeout":600,
    "method":"chacha20-ietf-poly1305"
}
EOF

cat >/etc/systemd/system/shadowsocks.service<<EOF
[Unit]
Description=Shadowsocks Server
After=network.target
[Service]
ExecStart=/usr/bin/ss-server -c /etc/shadowsocks-libev/config.json
Restart=on-abort
[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload && systemctl enable shadowsocks.service && systemctl restart shadowsocks.service
    cd ..
    rm -rf shadowsocks-libev tcp-wss.sh
    clear
}

client_v2ray(){
    echo
    echo "��װ�Ѿ����"
    echo
    echo "===========v2ray���ò���============"
    echo "��ַ��${domain}"
    echo "�˿ڣ�443/8080"
    echo "UUID��${v2uuid}"
    echo "���ܷ�ʽ��aes-128-gcm"
    echo "����Э�飺ws"
    echo "·����/${v2path}"
    echo "�ײ㴫�䣺tls"
    echo "ע�⣺8080�������˿ڲ���Ҫ��tls"
    echo
}

client_sslibev(){
    echo
    echo "��װ�Ѿ����"
    echo
    echo "===========Shadowsocks���ò���============"
    echo "��ַ��0.0.0.0"
    echo "�˿ڣ�10240"
    echo "���룺${v2uuid}"
    echo "���ܷ�ʽ��chacha20-ietf-poly1305"
    echo "����Э�飺tcp"
    echo
}

start_menu(){
    clear
    echo " ================================================== "
    echo " ��̳��https://1024.day                              "
    echo " ���ܣ�һ����װShadowsocks-libev��v2ray+ws+tls����    "
    echo " ϵͳ��Ubuntu��Debian��CentOS                        "
    echo " ================================================== "
    echo
    echo " 1. ��װShadowsocks-libev"
    echo " 2. ��װv2ray+ws+tls"
    echo " 3. ͬʱ��װ�������ִ���"
    echo " 0. �˳��ű�"
    echo
    read -p "����������:" num
    case "$num" in
    1)
    install_sslibev
    client_sslibev
    ;;
    2)
    install_precheck
    install_nginx
    acme_ssl
    install_v2ray
    client_v2ray
    ;;
    3)
    install_precheck
    install_nginx
    acme_ssl
    install_v2ray
    install_sslibev
    client_v2ray
    client_sslibev
    ;;
    0)
    exit 1
    ;;
    *)
    clear
    echo "��������ȷ����"
    sleep 2s
    start_menu
    ;;
    esac
}

start_menu