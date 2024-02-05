#!/usr/bin/env bash

read -p "Enter node address: " NODE
current_dir=$(pwd)
if [ "$current_dir" != "/opt/murzilla" ]; then
    echo "Current directory is not /opt/murzilla, moving..."
    cd /opt && sudo mkdir murzilla && sudo chmod 777 murzilla && sudo chown $USER:$USER murzilla
    sudo mv $current_dir /opt
else
    echo "Already in /opt/murzilla"
fi

cd /opt/murzilla
mkdir temp apps
sudo chmod 777 data
echo PATH="$PATH:/home/$USER/.local/bin:/opt/firebird/bin:/usr/local/go/bin:$PWD/bin" | sudo tee -a /etc/environment
echo MURZILLA="$PWD" | sudo tee -a /etc/environment
echo IPFS_PATH="/opt/murzilla/data/.ipfs" | sudo tee -a /etc/environment
sudo sed -i 's/usr\/local\/sbin/opt\/firebird\/bin\:\/usr\/local\/sbin/g' /etc/sudoers
source /etc/environment
echo -e "PATH=$PATH\nMURZILLA=$MURZILLA\nIPFS_PATH=$IPFS_PATH\n$(sudo crontab -l)\n" | sudo crontab -
sudo apt update
sudo DEBIAN_FRONTEND=noninteractive apt full-upgrade -yq
sudo DEBIAN_FRONTEND=noninteractive apt install -y docker.io docker-compose build-essential libssl-dev libffi-dev python3-dev python3-pip python3-venv tmux
sudo usermod -aG docker $USER
python3 -m venv venv
source venv/bin/activate
pip3 install feedparser fdb
wget -O temp/firebird.tar.gz https://github.com/FirebirdSQL/firebird/releases/download/v5.0.0/Firebird-5.0.0.1306-0-linux-x64.tar.gz
tar xvzf temp/firebird.tar.gz -C temp
sudo DEBIAN_FRONTEND=noninteractive apt install -y libtommath-dev
cd temp && find . -type d -name "Firebird*" -exec mv {} firebird \;
cd firebird
echo "vm.max_map_count = 256000" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p /etc/sysctl.conf
sudo ./install.sh << 'EOF'

murzilla
EOF
sudo usermod -a -G firebird $USER
cd /opt/murzilla

wget -O temp/go.tar.gz https://go.dev/dl/go1.21.5.linux-amd64.tar.gz
sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf temp/go.tar.gz
export PATH=$PATH:/usr/local/go/bin
go version
git clone -b v1.53.2 --recurse-submodules https://github.com/anacrolix/torrent temp/torrent
go install github.com/anacrolix/torrent/cmd/...@latest
cd /opt/murzilla/temp/torrent/fs/cmd/torrentfs
go install
cd /opt/murzilla
cp ~/go/bin/* bin/

export IPFS_PATH=/opt/murzilla/data/.ipfs
wget -O temp/kubo.tar.gz https://github.com/ipfs/kubo/releases/download/v0.26.0/kubo_v0.26.0_linux-amd64.tar.gz
tar xvzf temp/kubo.tar.gz -C temp
sudo mv temp/kubo/ipfs /usr/local/bin/ipfs
ipfs init --profile server
ipfs config --json Experimental.FilestoreEnabled true
ipfs config --json Pubsub.Enabled true
ipfs config --json Ipns.UsePubsub true
echo -e "\
[Unit]\n\
Description=InterPlanetary File System (IPFS) daemon\n\
Documentation=https://docs.ipfs.tech/\n\
After=network.target\n\
\n\
[Service]\n\
MemorySwapMax=0\n\
TimeoutStartSec=infinity\n\
Type=notify\n\
User=$USER\n\
Group=$USER\n\
Environment=IPFS_PATH=/opt/murzilla/data/.ipfs\n\
ExecStart=/usr/local/bin/ipfs daemon --enable-gc\n\
Restart=on-failure\n\
KillSignal=SIGINT\n\
\n\
[Install]\n\
WantedBy=default.target\n\
" | sudo tee /etc/systemd/system/ipfs.service
sudo systemctl daemon-reload
sudo systemctl enable ipfs
sudo systemctl restart ipfs

echo -e "\
[Unit]\n\
Description=InterPlanetary File System (IPFS) subscription\n\
After=network.target\n\
\n\
[Service]\n\
Type=simple\n\
User=$USER\n\
Group=$USER\n\
Environment=IPFS_PATH=/opt/murzilla/data/.ipfs\n\
ExecStartPre=/usr/bin/sleep 9\n\
ExecStart=/opt/murzilla/bin/ipfssub.sh\n\
Restart=on-failure\n\
KillSignal=SIGINT\n\
\n\
[Install]\n\
WantedBy=default.target\n\
" | sudo tee /etc/systemd/system/ipfssub.service
sudo systemctl daemon-reload
sudo systemctl enable ipfssub
sudo systemctl restart ipfssub
sleep 29

str=$(ipfs id) && echo $str | cut -c10-61 > /opt/murzilla/data/id.txt
(echo -n "$(date) Murzilla system is installed. ID=" && cat /opt/murzilla/data/id.txt) >> /opt/murzilla/data/log.txt
ipfspub 'Initial message'
ipfs pubsub pub murzilla /opt/murzilla/data/log.txt

echo -e "$(sudo crontab -l)\n@reboot echo \"\$(date) System is rebooted\" >> /opt/murzilla/data/log.txt\n* * * * * su $USER -c \"bash /opt/murzilla/bin/cron.sh\"" | sudo crontab -

sudo apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt install -y ca-certificates curl gnupg
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
NODE_MAJOR=20
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" | sudo tee /etc/apt/sources.list.d/nodesource.list
sudo apt-get update && sudo apt-get install nodejs -y
node -v
npm -v

sudo sh -c 'echo "deb https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
sudo apt-get update
sudo apt-get -y install postgresql-16

sudo su - postgres <<EOF
psql -U postgres -c "CREATE USER murzilla WITH PASSWORD 'murzilla';"
psql -U postgres -c "CREATE DATABASE murzilla OWNER murzilla;"
EOF

sudo DEBIAN_FRONTEND=noninteractive apt install -y apache2 php php-apcu php-bcmath php-cli php-common php-curl php-gd php-gmp php-imagick php-intl php-mbstring php-mysql php-zip php-xml
sudo phpenmod bcmath gmp imagick intl
wget -O temp/latest.zip https://download.nextcloud.com/server/releases/latest-28.zip
cd temp; unzip latest.zip; sudo mv nextcloud /var/www/nextcloud; cd ..
sudo chown -R www-data:www-data /var/www/nextcloud/
sudo a2dissite 000-default.conf
sudo systemctl reload apache2
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/apache.key -out /etc/ssl/certs/apache.crt -subj "/CN=$NODE"
#sudo openssl dhparam -out /etc/ssl/certs/dhparam.pem 4096
sudo tee /etc/apache2/conf-available/ssl-params.conf<<EOF
SSLCertificateFile /etc/ssl/certs/apache.crt
SSLCertificateKeyFile /etc/ssl/private/apache.key
SSLCipherSuite EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH
SSLProtocol All -SSLv2 -SSLv3 -TLSv1 -TLSv1.1
SSLHonorCipherOrder On
SSLCompression off
SSLSessionTickets Off
SSLUseStapling on
SSLStaplingCache "shmcb:logs/stapling-cache(150000)"
#SSLOpenSSLConfCmd DHParameters "/etc/ssl/certs/dhparam.pem"
EOF
sudo a2enconf ssl-params
sudo tee /etc/apache2/sites-available/nextcloud.conf <<EOF
<VirtualHost *:80>
   ServerName cloud

   RewriteEngine On
   RewriteCond %{HTTPS} off
   RewriteRule ^(.*)$ https://%{HTTP_HOST}$1 [R=301,L]
</VirtualHost>
<VirtualHost *:443>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/nextcloud
    ServerName cloud
    <Directory "/var/www/nextcloud/">
        Options MultiViews FollowSymlinks
        AllowOverride All
        Order allow,deny
        Allow from all
    </Directory>
    TransferLog /var/log/apache2/nextcloud.log
    ErrorLog /var/log/apache2/nextcloud.log
    SSLEngine on
    Header always set Strict-Transport-Security "max-age=15552000; includeSubDomains"
</VirtualHost>
EOF
sudo a2ensite nextcloud.conf
sudo systemctl reload apache2

cat /etc/php/8.1/apache2/php.ini | grep 'memory_limit = '
cat /etc/php/8.1/apache2/php.ini | grep 'upload_max_filesize ='
cat /etc/php/8.1/apache2/php.ini | grep 'max_execution_time ='
cat /etc/php/8.1/apache2/php.ini | grep 'post_max_size ='
cat /etc/php/8.1/apache2/php.ini | grep 'date.timezone ='
cat /etc/php/8.1/apache2/php.ini | grep 'opcache.enable='
cat /etc/php/8.1/apache2/php.ini | grep 'opcache.interned_strings_buffer='
cat /etc/php/8.1/apache2/php.ini | grep 'opcache.max_accelerated_files='
cat /etc/php/8.1/apache2/php.ini | grep 'opcache.memory_consumption='
cat /etc/php/8.1/apache2/php.ini | grep 'opcache.save_comments='
cat /etc/php/8.1/apache2/php.ini | grep 'opcache.revalidate_freq='

sudo sed -i 's/memory_limit = 128M/memory_limit = 512M/g' /etc/php/8.1/apache2/php.ini
sudo sed -i 's/upload_max_filesize = 2M/upload_max_filesize = 200M/g' /etc/php/8.1/apache2/php.ini
sudo sed -i 's/max_execution_time = 30/max_execution_time = 360/g' /etc/php/8.1/apache2/php.ini
sudo sed -i 's/post_max_size = 8M/post_max_size = 200M/g' /etc/php/8.1/apache2/php.ini
sudo sed -i 's/;date.timezone =/date.timezone = Europe\/Moscow/g' /etc/php/8.1/apache2/php.ini
sudo sed -i 's/;opcache.enable=1/opcache.enable=1/g' /etc/php/8.1/apache2/php.ini
sudo sed -i 's/;opcache.interned_strings_buffer=8/opcache.interned_strings_buffer=8/g' /etc/php/8.1/apache2/php.ini
sudo sed -i 's/;opcache.max_accelerated_files=10000/opcache.max_accelerated_files=10000/g' /etc/php/8.1/apache2/php.ini
sudo sed -i 's/;opcache.memory_consumption=128/opcache.memory_consumption=128/g' /etc/php/8.1/apache2/php.ini
sudo sed -i 's/;opcache.save_comments=1/opcache.save_comments=1/g' /etc/php/8.1/apache2/php.ini
sudo sed -i 's/;opcache.revalidate_freq=2/opcache.revalidate_freq=1/g' /etc/php/8.1/apache2/php.ini

cat /etc/php/8.1/apache2/php.ini | grep 'memory_limit = '
cat /etc/php/8.1/apache2/php.ini | grep 'upload_max_filesize ='
cat /etc/php/8.1/apache2/php.ini | grep 'max_execution_time ='
cat /etc/php/8.1/apache2/php.ini | grep 'post_max_size ='
cat /etc/php/8.1/apache2/php.ini | grep 'date.timezone ='
cat /etc/php/8.1/apache2/php.ini | grep 'opcache.enable='
cat /etc/php/8.1/apache2/php.ini | grep 'opcache.interned_strings_buffer='
cat /etc/php/8.1/apache2/php.ini | grep 'opcache.max_accelerated_files='
cat /etc/php/8.1/apache2/php.ini | grep 'opcache.memory_consumption='
cat /etc/php/8.1/apache2/php.ini | grep 'opcache.save_comments='
cat /etc/php/8.1/apache2/php.ini | grep 'opcache.revalidate_freq='

#memory_limit = 512M
#upload_max_filesize = 200M
#max_execution_time = 360
#post_max_size = 200M
#date.timezone = Europe/Moscow
#opcache.enable=1
#opcache.interned_strings_buffer=8
#opcache.max_accelerated_files=10000
#opcache.memory_consumption=128
#opcache.save_comments=1
#opcache.revalidate_freq=1

sudo a2enmod dir env headers mime rewrite ssl
sudo systemctl restart apache2

sudo DEBIAN_FRONTEND=noninteractive apt install -y libapache2-mod-php imagemagick ffmpeg php-bz2 php-redis redis-server unzip redis-server php-redis cron ncdu lnav net-tools iotop htop php-json

sudo DEBIAN_FRONTEND=noninteractive apt install -y php-pgsql
sudo phpenmod pgsql pdo_pgsql
sudo systemctl restart apache2

cd /var/www/nextcloud/
sudo -u www-data php occ  maintenance:install \
--database='pgsql' --database-name='murzilla' \
--database-user='murzilla' --database-pass='murzilla' \
--admin-user='murzilla' --admin-pass='murzilla'

sudo sed -i "s/0 => 'localhost',/0 => 'localhost',\n    1 => '$NODE',/g" /var/www/nextcloud/config/config.php

echo -e "$(sudo crontab -l)\n*/5  *  *  *  * sudo -u www-data php -f /var/www/nextcloud/cron.php\n* * * * * sudo -u www-data /opt/murzilla/bin/filesscan" | sudo crontab -

sudo -u www-data php occ app:enable news --force
sudo -u www-data php occ background:cron
sudo -u www-data php occ db:add-missing-indices
sudo -u www-data php occ news:feed:add murzilla https://habr.com/ru/rss/all/all/

sudo -u www-data mkdir /var/www/nextcloud/data/murzilla/files/torrentin
sudo -u www-data mkdir /var/www/nextcloud/data/murzilla/files/torrentout
sudo -u www-data mkdir /var/www/nextcloud/data/murzilla/files/magnetin
sudo mkdir /var/www/torrentdown
sudo chown -R www-data:www-data /var/www/torrentdown
echo -e "\
[Unit]\n\
Description=TorrentFS daemon\n\
After=network.target\n\
\n\
[Service]\n\
Type=simple\n\
User=www-data\n\
Group=www-data\n\
ExecStart=/opt/murzilla/bin/torrentfs -mountDir=/var/www/nextcloud/data/murzilla/files/torrentout -metainfoDir=/var/www/nextcloud/data/murzilla/files/torrentin -downloadDir=/var/www/torrentdown\n\
Restart=on-failure\n\
KillSignal=SIGINT\n\
\n\
[Install]\n\
WantedBy=default.target\n\
" | sudo tee /etc/systemd/system/torrentfs.service
sudo systemctl daemon-reload
sudo systemctl enable torrentfs
sudo systemctl restart torrentfs
sudo -u www-data php /var/www/nextcloud/occ files:scan --all

cd /opt/murzilla
sleep 9
rm -rf temp
mkdir temp
sudo reboot
