#!/bin/bash
set -e

UNIT_NAME=proxy
BINARY=rmfake-proxy
DESTINATION="/home/root/rmfakecloud"

echo ""
echo "rmFakeCloud proxy installer"
echo ""



# Create destination folder

function unpack(){
    mkdir -p ${DESTINATION}
    systemctl stop ${UNIT_NAME} || true
    # Find __ARCHIVE__ maker, read archive content and decompress it
    ARCHIVE=$(awk '/^__ARCHIVE__/ {print NR + 1; exit 0; }' "${0}")
    tail -n+${ARCHIVE} "${0}" | gunzip > ${DESTINATION}/${BINARY}
    chmod +x  ${DESTINATION}/${BINARY}
}

# marks all as unsynced so that they are not deleted
function fixsync(){
    grep sync ~/.local/share/remarkable/xochitl/*.metadata -l | xargs sed -i 's/synced\": true/synced\": false/'
} 

function install_proxyservice(){
cloudurl=$1
echo "Setting cloud sync to: ${cloudurl}"
workdir=$DESTINATION
cat > $workdir/proxy.cfg <<EOF
URL=
EOF
cat > /etc/systemd/system/${UNIT_NAME}.service <<EOF
[Unit]
Description=reverse proxy
#StartLimitIntervalSec=600
#StartLimitBurst=4
After=home.mount

[Service]
Environment=HOME=/home/root
#EnvironmentFile=$workdir/proxy.cfg
WorkingDirectory=$workdir
ExecStart=$workdir/${BINARY} -cert $workdir/proxy.crt -key $workdir/proxy.key ${cloudurl}

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable ${UNIT_NAME}
systemctl restart ${UNIT_NAME}
}

function uninstall(){
    systemctl stop ${UNIT_NAME}
    systemctl disable ${UNIT_NAME}
    #rm proxy.key proxy.crt ca.crt ca.srl ca.key proxy.pubkey proxy.csr csr.conf proxy.cfg
    rm /usr/local/share/ca-certificates/ca.crt
    update-ca-certificates --fresh
    rm /etc/systemd/system/proxy.service
    sed -i '/# rmfake_start/,/# rmfake_end/d' /etc/hosts
    echo "Marking files as not synced to prevent data loss"
    fixsync
    rm -fr $DESTINATION
    echo "You can restart xochitl now"
}

function generate_certificates(){
# thanks to  https://gist.github.com/Soarez/9688998
pushd $DESTINATION

cat <<EOF > csr.conf
[ req ]
default_bits = 2048
default_keyfile = proxy.key
encrypt_key = no
default_md = sha256
prompt = no
utf8 = yes
distinguished_name = dn
req_extensions = ext
x509_extensions = caext

[ dn ]
C = AA
ST = QQ
L = JJ
O  = the culture
CN = *.appspot.com

[ ext ]
subjectAltName=@san
basicConstraints=CA:FALSE
subjectKeyIdentifier = hash


[ caext ]
subjectAltName=@san

[ san ]
DNS.1 = *.appspot.com
DNS.2 = my.remarkable.com
DNS.3 = internal.cloud.remarkable.com
DNS.4 = ping.remarkable.com
DNS.5 = *.remarkable.com
# DNS.3 = any additional hosts
EOF

# ca
if [ ! -f ca.crt ]; then 
    echo "Generating ca..."
    openssl genrsa -out ca.key 2048
    openssl req -new -sha256 -x509 -key ca.key -out ca.crt -days 3650 -subj /CN=rmfakecloud
    rm proxy.key || true
    rm proxy.pubkey || true
else
    echo "CA exists"
fi

if [ ! -f proxy.key ]; then 
    echo "Generating proxy keys..."
    openssl genrsa -out proxy.key 2048
    rm proxy.pubkey || true
else
    echo "Private key exists"
fi

if [ ! -f proxy.pubkey ]; then 
    openssl rsa -in proxy.key -pubout -out proxy.pubkey
    rm proxy.crt || true
else
    echo "Pub key exists"
fi

if [ ! -f proxy.crt ]; then 
    openssl req -new -config ./csr.conf -key proxy.key -out proxy.csr 

    # Signing
    openssl x509 -req  -in proxy.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out proxy.crt -days 3650 -extfile csr.conf -extensions caext
    #cat proxy.crt ca.crt > proxy.bundle.crt

    echo "showing result"
    #openssl x509 -in proxy.bundle.crt -text -noout 

    echo "Generation complete"
else
    echo "crt exists"
fi
popd
}

function install_certificates(){
    certdir="/usr/local/share/ca-certificates"
    certname=$certdir/ca.crt
    if [ -f $certname ]; then
        echo "The cert has been already installed, it will be removed and reinstalled!!!"
        rm  $certname
        update-ca-certificates --fresh
    fi
    mkdir -p $certdir
    cp $DESTINATION/ca.crt $certdir/
    update-ca-certificates --fresh
}

function patch_hosts(){
    if  ! grep rmfake_start /etc/hosts ; then
        cat <<EOF >> /etc/hosts
# rmfake_start
127.0.0.1 hwr-production-dot-remarkable-production.appspot.com
127.0.0.1 service-manager-production-dot-remarkable-production.appspot.com
127.0.0.1 local.appspot.com
127.0.0.1 my.remarkable.com
127.0.0.1 internal.cloud.remarkable.com
127.0.0.1 ping.remarkable.com
# rmfake_end
EOF
    fi

}

function getproxy(){
    read -p "Enter your own cloud url: " url
    echo $url
}

function doinstall(){
    unpack
    generate_certificates
    install_certificates
    # install proxy
    url=$(getproxy)
    install_proxyservice $url
    patch_hosts
    systemctl stop xochitl
    fixsync
    systemctl start xochitl
}


case $1 in
    "uninstall" )
        uninstall
     ;;

     "install" )
        doinstall
     ;;

     "setproxy" )
        shift 1
        url=$1
        if [ $# -lt 1 ]; then
             url=$(getproxy)
        fi
        install_proxyservice $url
     ;;

     * )
cat <<EOF
Usage:

install
    installs

uninstall
    uninstall

setproxy [cloudurl]
    changes the cloud address to

EOF
         ;;

esac

# Exit from the script with success (0)
exit 0

__ARCHIVE__
