# rmfakecloud-proxy
Single-minded HTTPS reverse proxy

(forked from https://github.com/yi-jiayu/secure)


## Usage
```
usage: secure [-addr host:port] -cert certfile -key keyfile upstream
  -addr string
        listen address (default ":443")
  -cert string
        path to cert file
  -key string
        path to key file
  upstream string
        upstream url
```

### Example
```
secure -cert cert.pem -key key.pem http://localhost:6060
```

