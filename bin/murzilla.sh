#!/usr/bin/env bash

echo "Murzilla - journal of titles / Мурзилла - журнал заголовков"

cd /opt/murzilla
source venv/bin/activate

DB_FILE="/opt/murzilla/data/rss.fdb"

if [ ! -f "$DB_FILE" ]; then

  echo "Creating Firebird database $DB_FILE"

  isql <<EOF
    CREATE DATABASE 'localhost:$DB_FILE' user 'SYSDBA' password 'murzilla';
EOF

  if [ $? -eq 0 ]; then
    echo "Database created successfully"
  else
    echo "Failed to create database"
    exit 1
  fi

else

  echo "Database $DB_FILE already exists"

fi

python3 bin/rssparse.py
