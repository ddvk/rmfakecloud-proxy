# rmfakecloud-proxy
Single-minded HTTPS reverse proxy

(forked from https://github.com/yi-jiayu/secure)

## Installation



### Manual
Download `installer-rm12.sh` for rm1/2 or `installer-rmpro.sh` on a pc.  
Transnfer to the tablet with `scp` / `WinSCP`  
run installer on the tablet over ssh  
```
chmod +x installer-xxx.sh
./installer-xxx.sh
```

### Use toltec if supported
`opkg install rmfakecloud-proxy`

### rmpro
To make it permanent, make root writable and unmount /etc first e.g.
```
mount -o remount,rw /
umount -R /etc
./installer-rmpro.sh
```

## Usage
```
usage: rmfakecloud-proxy [-addr host:port] -cert certfile -key keyfile upstream
  -addr string
        listen address (default ":443")
  -cert string
        path to cert file
  -key string
        path to key file
  -c configfile
  upstream string
        upstream url
```

### Example
```
rmfakecloud-proxy -cert cert.pem -key key.pem http://localhost:6060
```

## Configfile
```yaml
cert: proxy.crt 
key: proxy.key
upstream: https://somehost:123
#addr: :443
```

