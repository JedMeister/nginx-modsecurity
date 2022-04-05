#!/bin/bash -e
#
# (c) 2022 TurnKey GNU/Linux <admin@turnkeylinux.org>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License at (http://www.gnu.org/licenses/) for
# more details.

## create and enter build dir
BUILD_DIR=$PWD/modsec_build
mkdir -p $BUILD_DIR
cd $BUILD_DIR

## Download and unpack Nginx source package (from Debian)
deb_nginx_v=$(apt-cache policy nginx-light \
        | sed -En "s|^.*Candidate: ([1-9]\.[0-9].*)|\1|p")
nginx_v=$(echo $deb_nginx_v | sed -En "s|([0-9\.]+)-.*|\1|p")

base_url=https://deb.debian.org/debian/pool/main/n/nginx
curl -o nginx_${deb_nginx_ver}.dsc $base_url/nginx_${deb_nginx_ver}.dsc
files=$(grep 'Files:' -A99 nginx_${deb_nginx_v}.dsc \
    | sed -En "s|.*(nginx_${nginx_v}.*)|\1|p")

for dl_file in $files; do
    curl -o $dl_file $URL/$dl_file
done
dpkg-source -x nginx_${deb_nginx_v}.dsc

## collect default Debian build options and tweak as required
OPTS=$(/usr/sbin/nginx -V 2>&1 | \
    sed -n "s|--|\n--|g; s|^configure arguments: \n||p;")
CC_OPTS=$(echo "$OPTS" | sed -En "\|^--with-cc-opt| s|^.*='(.*)'|\1|"p)
LD_OPTS=$(echo "$OPTS" | sed -En "\|^--with-ld-opt| s|^.*='(.*)'|\1|"p)

OPTS=$(echo "$OPTS" | grep -v -- ^--with-cc-opt)
OPTS=$(echo "$OPTS" | grep -v -- ^--with-ld-opt)
# remove default modules see
# https://github.com/SpiderLabs/ModSecurity-nginx/issues/159 and
# https://github.com/SpiderLabs/ModSecurity-nginx/issues/117
OPTS=$(echo "$OPTS" | grep -v -- ^--add-dynamic-module)

## clone reqd repo and compile
git clone --depth 1 https://github.com/SpiderLabs/ModSecurity-nginx.git
cd nginx-1.*
./configure --with-cc-opt="$CC_OPTS" --with-ld-opt="$LD_OPTS" $OPTS \
    --add-dynamic-module=../ModSecurity-nginx
make modules
cd $(dirname $BUILD_DIR)

## setup nginx modsecurity file structure
mkdir -p etc/nginx/{modules-available,modsec,snippets}
mkdir -p usr/lib/libnginx-modsecurity

cp nginx-1.*/objs/ngx_http_modsecurity_module.so usr/lib/libnginx-modsecurity/

## nginx modsecurity configuration
cat > etc/nginx/modules-available/modsecurity.conf <<EOF
load_module /usr/lib/libnginx-modsecurity/ngx_http_modsecurity_module.so;
EOF
cat > etc/nginx/snippets/modsecurity.conf <<EOF
modsecurity on;
modsecurity_rules_file /etc/nginx/modsec/main.conf;
EOF

## Get modsecurity config
# get Debian modsecurity version
modsec_v=$(apt-cache policy libmodsecurity3 | sed -En "s|^ *Candidate: ([0-9\.]+).*$|\1|p")
base_url=https://raw.githubusercontent.com/SpiderLabs/ModSecurity/v${modsec_v}
curl -o etc/nginx/modsec/modsecurity.conf $base_url/modsecurity.conf-recommended
curl -o etc/nginx/modsec/unicode.mapping $base_url/unicode.mapping
# enable modsecurity and rules (provided by )
cat > etc/nginx/modsec/main.conf <<EOF
Include "/etc/nginx/modsec/modsecurity.conf"
# OWASP Core Rule Set provided by 'modsecurity-crs' package
Include "/usr/share/modsecurity-crs/owasp-crs.load"
EOF
