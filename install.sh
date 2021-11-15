#!/bin/bash -e

# create and enter build dir
BUILD_DIR=modsec_build
mkdir -p $BUILD_DIR

# download and unpack source package 
NGINX_VER=$(apt-cache policy nginx | grep Installed: | sed "s|^.*: \([1-9]\.[0-9].*\)|\1|")
URL=https://deb.debian.org/debian/pool/main/n/nginx #nginx_1.18.0-6.1.dsc
wget $URL/nginx_${NGINX_VER}.dsc
FILES=$(grep "Files:" -A3 nginx_${NGINX_VER}.dsc | tail -3 | sed "s|.*nginx|nginx|")
for dl_file in $FILES; do
    wget $URL/$dl_file
done
dpkg-source -x nginx_${NGINX_VER}.ds

# collect default Debian build options and tweak as required
OPTS=$(/usr/sbin/nginx -V 2>&1 | \
    sed -n "s|--|\n--|g; s|^configure arguments: \n||p;")
CC_OPTS=$(echo "$OPTS" | sed -n "\|^--with-cc-opt| s|^.*='\(.*\)'|\1|"p)
LD_OPTS=$(echo "$OPTS" | sed -n "\|^--with-ld-opt| s|^.*='\(.*\)'|\1|"p)

OPTS=$(echo "$OPTS" | grep -v -- ^--with-cc-opt)
OPTS=$(echo "$OPTS" | grep -v -- ^--with-ld-opt)
# remove default modules see
# https://github.com/SpiderLabs/ModSecurity-nginx/issues/159 and
# https://github.com/SpiderLabs/ModSecurity-nginx/issues/117
OPTS=$(echo "$OPTS" | grep -v -- ^--add-dynamic-module)

# clone reqd repo and compile, setup and enable nginx modsecurity
git clone --depth 1 https://github.com/SpiderLabs/ModSecurity-nginx.git
cd nginx-1.*
./configure --with-cc-opt="$CC_OPTS" --with-ld-opt="$LD_OPTS" $OPTS \
    --add-dynamic-module=../ModSecurity-nginx
make modules
mkdir -p /etc/nginx/{modules,modsec}
cp objs/ngx_http_modsecurity_module.so /etc/nginx/modules/
echo "load_module /etc/nginx/modules/ngx_http_modsecurity_module.so;" \
    > /etc/nginx/modules-available/modsecurity.conf
ln -sf /etc/nginx/modules-available/modsecurity.conf /etc/nginx/modules-enabled/
curl -o /etc/nginx/modsec/modsecurity.conf \
    https://raw.githubusercontent.com/SpiderLabs/ModSecurity/v3/master/modsecurity.conf-recommended
curl -o /etc/nginx/modsec/unicode.mapping \
    https://raw.githubusercontent.com/SpiderLabs/ModSecurity/v3/master/unicode.mapping
cat > /etc/nginx/modsec/main.conf <<EOF
Include "/etc/nginx/modsec/modsecurity.conf"
SecRule ARGS:testparam "@contains test" "id:1234,deny,status:403"
EOF
cat > /etc/nginx/include/modsecurity.conf <<EOF
modsecurity on;
modsecurity_rules_file /etc/nginx/modsec/main.conf;
EOF

