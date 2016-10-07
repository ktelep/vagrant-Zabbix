#!/bin/sh
# -------------------------------------------------
# Add repos and install packages
# -------------------------------------------------
wget http://repo.zabbix.com/zabbix/3.2/ubuntu/pool/main/z/zabbix-release/zabbix-release_3.2-1+trusty_all.deb
dpkg -i 'zabbix-release_3.2-1+trusty_all.deb'
apt-get -y update
export DEBIAN_FRONTEND=noninteractive
echo 'mysql-server mysql-server/root_password password zabbix' | debconf-set-selections
echo 'mysql-server mysql-server/root_password_again password zabbix' | debconf-set-selections
apt-get -y install mysql-server mysql-client
apt-get -y install zabbix-server-mysql zabbix-frontend-php zabbix-agent

# Start the DB, set the password and install base DB
service mysql start
cd /usr/share/doc/zabbix-server-mysql
echo "create database zabbix;" | mysql -u root -pzabbix
zcat create.sql.gz | mysql -uroot -pzabbix zabbix

# Update configuration for Zabbix
sed -i 's/# DBPassword=/DBPassword=zabbix/g' /etc/zabbix/zabbix_server.conf
sed -i 's/DBUser=.*/DBUser=root/g' /etc/zabbix/zabbix_server.conf
sed -i "s/Hostname=Zabbix server/Hostname=`hostname`/" /etc/zabbix/zabbix_agentd.conf

# Startup Zabbix Server
service zabbix-server start

# Setup PHp configuration
sed -i 's/post_max_size = 8M/post_max_size = 16M/'  /etc/apache2/conf-enabled/zabbix.conf
sed -i 's/max_execution_time = 30/max_execution_time = 300/' /etc/apache2/conf-enabled/zabbix.conf
sed -i 's/max_input_time = 60/max_input_time = 300/' /etc/apache2/conf-enabled/zabbix.conf
sed -i 's/# php_value date.timezone Europe\/Riga/php_value date.timezone America\/New_York/' /etc/apache2/conf-enabled/zabbix.conf

# Start Zabbix HTTP service
service apache2 restart
