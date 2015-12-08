#!/bin/sh
# -------------------------------------------------
# Add repos and install packages
# -------------------------------------------------
echo '
[nginx]
name=nginx repo
baseurl=http://nginx.org/packages/centos/6/$basearch/
gpgcheck=0
enabled=1' > /etc/yum.repos.d/nginx.repo

yum update -y
yum install -y libtool git python-devel texinfo
yum install -y mysql-server php-mysql php-bcmath php-gd php-fpm php-xml php-ldap php-mbstring wget libcurl-devel openldap-devel java-1.7.0-openjdk-devel net-snmp-devel libxml2-devel mysql-devel nginx vim

# -------------------------------------------------
# Start mysql
# -------------------------------------------------
/etc/init.d/mysqld start

# -------------------------------------------------
# Grab zabbix source from SF and build
# -------------------------------------------------
mkdir -p /opt/sources/zabbix
cd /opt/sources/zabbix
wget http://sourceforge.net/projects/zabbix/files/ZABBIX%20Latest%20Stable/2.4.6/zabbix-2.4.6.tar.gz
tar zxvf zabbix-2.4.6.tar.gz 
cd zabbix-2.4.6
./configure --enable-server --enable-agent --prefix=/usr/local --sysconfdir=/etc --enable-java --with-mysql --with-libcurl --with-net-snmp --with-ldap --with-iconv --with-libxml2 && make && make install
groupadd zabbix
useradd -g zabbix zabbix


# -------------------------------------------------
# Setup MySQL database for Zabbix
# -------------------------------------------------

mysqladmin -uroot password 'topsecret'
cd /opt/sources/zabbix/zabbix-2.4.6/database/mysql
echo "create database zabbix;" | mysql -u root -ptopsecret
echo "source schema.sql;" | mysql -u root -ptopsecret zabbix
echo "source images.sql;" | mysql -u root -ptopsecret zabbix
echo "source data.sql;" | mysql -u root -ptopsecret zabbix

# -------------------------------------------------
# Configure zabbix server and copy start scripts
# -------------------------------------------------
cp /opt/sources/zabbix/zabbix-2.4.6/misc/init.d/fedora/core5/zabbix_server /etc/init.d/
cp /opt/sources/zabbix/zabbix-2.4.6/misc/init.d/fedora/core5/zabbix_agentd /etc/init.d/
sed -i 's/# DBPassword=/DBPassword=topsecret/g' /etc/zabbix_server.conf

mkdir -p /var/www/zabbix
cp -r -p /opt/sources/zabbix/zabbix-2.4.6/frontends/php/* /var/www/zabbix/
chown nginx. /var/www/zabbix/*

# Set the hostname in the Zabbix config
sed -i "s/Hostname=Zabbix server/Hostname=`hostname`/" /etc/zabbix_agentd.conf

# -------------------------------------------------
# Start zabbix server and agentd
# -------------------------------------------------
/etc/init.d/zabbix_server start
/etc/init.d/zabbix_agentd start


# -------------------------------------------------
# Configure nginx.conf
# -------------------------------------------------
echo 'user  nginx;
worker_processes  1;

error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;


events {
    worker_connections  1024;
}


http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile        on;
    #tcp_nopush     on;

    keepalive_timeout  65;

    include /etc/nginx/conf.d/*.conf;
    gzip on;
    gzip_static on;
    gzip_comp_level 2;
    gzip_min_length 20240;
    gzip_proxied expired no-cache no-store private auth;
    gzip_types text/plain text/css application/x-javascript text/xml application/xml application/xml+rss text/javascript;
    gzip_disable "MSIE [1-6]\.";

    fastcgi_cache_path /var/cache/nginx levels=1:2 keys_zone=microcache:10m max_size=1000m inactive=60m;

}' > /etc/nginx/nginx.conf

# -------------------------------------------------
# Configure endpoint
# -------------------------------------------------
echo 'upstream php5-fpm-sock {
    server unix:/var/run/php-fpm/php-fpm.socket;
}

server {
    server_name localhost;
    set $cache_uri $request_uri;

    # POST requests and urls with a query string should always go to PHP
    if ($request_method = POST) {
      set $cache_uri '"'"'null cache'"'"';
    }
    if ($query_string != "") {
      set $cache_uri '"'"'null cache'"'"';
    }

    root /var/www/zabbix;
  error_log  /var/log/nginx/error.log;
  access_log  /var/log/nginx/access.log  main;
 
    location / {
        index index.html index.htm index.php;
  proxy_read_timeout 600;
    }

    location ~* \.(jpg|jpeg|gif|png|css|js|ico|xml)$ {
        access_log        off;
        log_not_found     off;
        expires           360d;
    }

    location ~ \.php$ {
        include /etc/nginx/fastcgi_params;
        set $skip_cache 1;
        if ($cache_uri != "null cache") {
           add_header X-Cache-Debug "$cache_uri $cookie_nocache $arg_nocache$arg_comment $http_pragma $http_authorization";
          set $skip_cache 0;
        }
        fastcgi_cache_bypass $skip_cache;
#        fastcgi_cache microcache;
        fastcgi_cache_key $scheme$host$request_uri$request_method;
        fastcgi_cache_valid any 8m;
        #fastcgi_cache_use_stale updating;
        fastcgi_cache_bypass $http_pragma;
        fastcgi_cache_use_stale updating error timeout invalid_header http_500;
        fastcgi_pass php5-fpm-sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME /var/www/zabbix$fastcgi_script_name;
  fastcgi_read_timeout 14400;
    }
}' > /etc/nginx/conf.d/default.conf

# --------------------------------------------
# PHP Configuration
# --------------------------------------------
sed -i 's/post_max_size = 8M/post_max_size = 16M/' /etc/php.ini
sed -i 's/max_execution_time = 30/max_execution_time = 300/' /etc/php.ini
sed -i 's/max_input_time = 60/max_input_time = 300/' /etc/php.ini
sed -i 's/;date.timezone =/date.timezone=America\/New_York/' /etc/php.ini

echo '[www]
listen = /var/run/php-fpm/php-fpm.socket
listen.backlog = -1
listen.owner = nginx
listen.group = nginx
listen.mode=0660

user = nginx
group = nginx
#request_slowlog_timeout = 10s
#slowlog = /var/log/php-fpm/slowlog-site.log
listen.allowed_clients = 127.0.0.1
pm = dynamic
pm.max_children = 20
pm.start_servers = 6
pm.min_spare_servers = 4
pm.max_spare_servers = 7
pm.max_requests = 150
pm.status_path = /status
request_terminate_timeout = 600s
rlimit_files = 131072
rlimit_core = unlimited
catch_workers_output = yes
env[HOSTNAME] = $HOSTNAME
env[TMP] = /tmp
env[TMPDIR] = /tmp
env[TEMP] = /tmp' > /etc/php-fpm.d/www.conf

mkdir -p /var/lib/php/session 
chown nginx. /var/lib/php/session

# --------------------------------------------
# Start Web Components
# --------------------------------------------
/etc/init.d/nginx start
/etc/init.d/php-fpm start


