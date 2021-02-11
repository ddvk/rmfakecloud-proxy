#!/bin/bash
SERVICE_NAME=proxy
DESTINATION="/home/root/rmfakecloud"

echo ""
echo "rmfakecloud proxy installer"
echo ""



# Create destination folder

function unpack(){
    mkdir -p ${DESTINATION}
    systemctl stop proxy || true
    # Find __ARCHIVE__ maker, read archive content and decompress it
    ARCHIVE=$(awk '/^__ARCHIVE__/ {print NR + 1; exit 0; }' "${0}")
    tail -n+${ARCHIVE} "${0}" | gunzip > ${DESTINATION}/${SERVICE_NAME}
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
cat > /etc/systemd/system/proxy.service <<EOF
[Unit]
Description=reverse proxy
#StartLimitIntervalSec=600
#StartLimitBurst=4
After=home.mount

[Service]
Environment=HOME=/home/root
#EnvironmentFile=$workdir/proxy.cfg
WorkingDirectory=$workdir
ExecStart=$workdir/${SERVICE_NAME} -cert $workdir/proxy.crt -key $workdir/proxy.key ${cloudurl}

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable ${SERVICE_NAME}
systemctl restart ${SERVICE_NAME}
}

function uninstall(){
    systemctl stop ${SERVICE_NAME}
    systemctl disable ${SERVICE_NAME}
    rm proxy.key proxy.crt ca.crt ca.srl ca.key proxy.pubkey proxy.csr csr.conf proxy.cfg
    rm /usr/local/share/ca-certificates/ca.crt
    rm /etc/systemd/system/proxy.service
    sed -i '/# rmfake_start/,/# rmfake_end/d' /etc/hosts
    echo "Marking files as not synced to prevent data loss"
    fixsync
    echo "You can restart xochitl now"
}

function generate_certificates(){
# thanks to  https://gist.github.com/Soarez/9688998

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
}
# Put your logic here (if you need)
function install_certificates(){
    certdir="/usr/local/share/ca-certificates"
    certname=$certdir/ca.crt
    if [ -f $certname ]; then
        echo "The cert has been already installed, it will be removed and reinstalled!!!"
        rm  $certname
        update-ca-certificates --fresh
    fi
    mkdir -p $certdir
    cp ca.crt $certdir/
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
# rmfake_end
EOF
    fi

}

function doinstall(){
    unpack
    generate_certificates
    install_certificates
    # install proxy
    url=getproxy
    installproxy.sh $url
    patch_hosts
    systemctl stop xochitl
    fixsync
    systemctl start xochitl
}

function getproxy(){
    read -p "Enter your own cloud url: " url
    echo $url
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
        echo $url
     ;;

     * )
     echo "params"
         ;;

esac

# Exit from the script with success (0)
exit 0

__ARCHIVE__
