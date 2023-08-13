# rmfakecloud-proxy
Single-minded HTTPS reverse proxy

(forked from https://github.com/yi-jiayu/secure)


## Usage
```
usage: rmfake-proxy [-addr host:port] -cert certfile -key keyfile upstream
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
rmfake-proxy -cert cert.pem -key key.pem http://localhost:6060
```

## Configfile
```yaml
cert: proxy.crt 
key: proxy.key
upstream: https://somehost:123
#addr: :443
```
