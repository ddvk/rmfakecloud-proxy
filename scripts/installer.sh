#!/bin/bash
set -e

UNIT_NAME=rmfakecloud-proxy
BINARY=rmfakecloud-proxy
DESTINATION="/home/root/rmfakecloud"


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
    grep sync ~/.local/share/remarkable/xochitl/*.metadata -l | xargs -r sed -i 's/synced\": true/synced\": false/'
} 

# Normalize Cloudflare token input (strips prefixes like "CF-Access-Client-Id:" or "cf-access-client-id:")
function normalize_cf_token(){
    local input="$1"
    # Remove leading/trailing whitespace
    input=$(echo "$input" | xargs)
    
    # Strip common prefixes (case-insensitive)
    if [[ "$input" =~ ^[Cc][Ff]-[Aa]ccess-[Cc]lient-[Ii]d:\ *(.+)$ ]]; then
        echo "${BASH_REMATCH[1]}"
    elif [[ "$input" =~ ^[Cc][Ff]-[Aa]ccess-[Cc]lient-[Ss]ecret:\ *(.+)$ ]]; then
        echo "${BASH_REMATCH[1]}"
    elif [[ "$input" =~ ^[Cc][Ff]-[Aa]ccess-[Cc]lient-[Ii]d=(.+)$ ]]; then
        echo "${BASH_REMATCH[1]}"
    elif [[ "$input" =~ ^[Cc][Ff]-[Aa]ccess-[Cc]lient-[Ss]ecret=(.+)$ ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo "$input"
    fi
}

function install_proxyservice(){
cloudurl=$1
cf_client_id=$2
cf_client_secret=$3
client_cert_file=$4
client_key_file=$5
echo "Setting cloud sync to: ${cloudurl}"
workdir=$DESTINATION

# Build ExecStart command with optional CF parameters
exec_start="$workdir/${BINARY} -cert $workdir/proxy.bundle.crt -key $workdir/proxy.key"

if [ -n "$cf_client_id" ] && [ -n "$cf_client_secret" ]; then
    exec_start="$exec_start -cf-client-id \"$cf_client_id\" -cf-client-secret \"$cf_client_secret\""
fi

if [ -n "$client_cert_file" ] && [ -n "$client_key_file" ]; then
    exec_start="$exec_start -client-cert \"$workdir/$client_cert_file\" -client-key \"$workdir/$client_key_file\""
fi

exec_start="$exec_start ${cloudurl}"

cat > /etc/systemd/system/${UNIT_NAME}.service <<EOF
[Unit]
Description=rmfakecloud reverse proxy
#StartLimitIntervalSec=600
#StartLimitBurst=4
After=home.mount

[Service]
Environment=HOME=/home/root
WorkingDirectory=$workdir
ExecStart=$exec_start

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
    rm /etc/systemd/system/${UNIT_NAME}.service
    sed -i '/# rmfake_start/,/# rmfake_end/d' /etc/hosts
    echo "Marking files as not synced to prevent data loss"
    echo "Stopping xochitl..."
    systemctl stop xochitl
    fixsync
    rm -fr $DESTINATION
    echo "Restart xochitl for the changes to take effect"
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
DNS.2 = *.remarkable.com
DNS.3 = *.cloud.remarkable.com
DNS.4 = *.cloud.remarkable.engineering
DNS.5 = *.rmfakecloud.localhost
DNS.6 = *.internal.cloud.remarkable.com
DNS.7 = *.tectonic.remarkable.com
DNS.8 = *.ping.remarkable.com
DNS.9 = *.internal.tctn.cloud.remarkable.com
EOF

# ca
if [ ! -f ca.crt ]; then 
    echo "Generating CA key and crt..."
    openssl genrsa -out ca.key 2048
    openssl req -new -sha256 -x509 -key ca.key -out ca.crt -days 3650 -subj /CN=rmfakecloud
    rm -f proxy.key
    rm -f proxy.pubkey
else
    echo "CA exists"
fi

if [ ! -f proxy.key ]; then 
    echo "Generating private key..."
    openssl genrsa -out proxy.key 2048
    rm -f proxy.pubkey
else
    echo "Private key exists"
fi

if [ ! -f proxy.pubkey ]; then 
    echo "Generating pub key..."
    openssl rsa -in proxy.key -pubout -out proxy.pubkey
    rm -f proxy.crt
else
    echo "Pub key exists"
fi

if [ ! -f proxy.crt ]; then 
    echo "Generating csr and crt..."
    openssl req -new -config ./csr.conf -key proxy.key -out proxy.csr 

    # Signing
    openssl x509 -req  -in proxy.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out proxy.crt -days 3650 -extfile csr.conf -extensions caext
    cat proxy.crt ca.crt > proxy.bundle.crt

    #echo "showing result"
    #openssl x509 -in proxy.bundle.crt -text -noout 

    echo "Generation complete!"
else
    echo "crt exists"
fi
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
127.0.0.1 ping.remarkable.com
127.0.0.1 internal.cloud.remarkable.com
127.0.0.1 eu.tectonic.remarkable.com
127.0.0.1 backtrace-proxy.cloud.remarkable.engineering
127.0.0.1 dev.ping.remarkable.com
127.0.0.1 dev.tectonic.remarkable.com
127.0.0.1 dev.internal.cloud.remarkable.com
127.0.0.1 eu.internal.tctn.cloud.remarkable.com
# rmfake_end
EOF
    fi

}

function getproxy(){
    read -p "Enter your own cloud url [http(s)://somehost:port] >" url
    echo $url
}

function get_cf_credentials(){
    read -p "Enter Cloudflare Access Client ID (optional, press Enter to skip): " cf_id
    cf_id=$(normalize_cf_token "$cf_id")
    
    if [ -n "$cf_id" ]; then
        read -p "Enter Cloudflare Access Client Secret: " cf_secret
        cf_secret=$(normalize_cf_token "$cf_secret")
    fi
    
    echo "$cf_id|$cf_secret"
}

function get_client_certificates(){
    read -p "Enter path to client certificate file (optional, press Enter to skip): " client_cert
    read -p "Enter path to client key file (optional, press Enter to skip): " client_key
    echo "$client_cert|$client_key"
}

function doinstall(){
    echo "Extracting embedded binary..."
    unpack
    pushd "${DESTINATION}"
    generate_certificates
    install_certificates
    # install proxy
    url=$1
    if [ -z $url ]; then
        url=$(getproxy)
    fi

    # Get Cloudflare credentials if not provided
    cf_creds=$(get_cf_credentials)
    cf_client_id=$(echo "$cf_creds" | cut -d'|' -f1)
    cf_client_secret=$(echo "$cf_creds" | cut -d'|' -f2)
    client_creds=$(get_client_certificates)
    client_cert_file=$(echo "$client_creds" | cut -d'|' -f1)
    client_key_file=$(echo "$client_creds" | cut -d'|' -f2)
    
    install_proxyservice "$url" "$cf_client_id" "$cf_client_secret" "$client_cert_file" "$client_key_file"

    echo "Patching /etc/hosts"
    patch_hosts
    echo "Stoping xochitl.."
    systemctl stop xochitl
    echo "Fixing sync status..."
    fixsync
    echo "Starting xochitl..."
    systemctl start xochitl
    popd
}


case $1 in
    "uninstall" )
        uninstall
        ;;

     "install" )
        shift 1
        url=$1
        shift 1 || true
        cf_client_id=$(normalize_cf_token "$1")
        shift 1 || true
        cf_client_secret=$(normalize_cf_token "$1")
        doinstall "$url" "$cf_client_id" "$cf_client_secret"
        ;;

     "gencert" )
        generate_certificates
        ;;

     "setcloud" )
        shift 1
        url=$1
        shift 1 || true
        cf_client_id=$(normalize_cf_token "$1")
        shift 1 || true
        cf_client_secret=$(normalize_cf_token "$1")
        
        if [ -z "$url" ]; then
            url=$(getproxy)
        fi
        
        if [ -z "$cf_client_id" ]; then
            cf_creds=$(get_cf_credentials)
            cf_client_id=$(echo "$cf_creds" | cut -d'|' -f1)
            cf_client_secret=$(echo "$cf_creds" | cut -d'|' -f2)
        fi

        install_proxyservice "$url" "$cf_client_id" "$cf_client_secret" "$client_cert_file" "$client_key_file"
        ;;

     * )

cat <<EOF
rmFakeCloud reverse proxy installer

Usage:

install [cloudurl] [cf-client-id] [cf-client-secret] [client-cert-file] [client-key-file]
    installs and asks for cloud url and optional Cloudflare credentials

uninstall
    uninstall, removes everything

gencert
    generate certificates

setcloud [cloudurl] [cf-client-id] [cf-client-secret] [client-cert-file] [client-key-file]
    changes the cloud address and optional Cloudflare credentials

EOF
        ;;

esac

exit 0

__ARCHIVE__
