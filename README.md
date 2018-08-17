# secure
Super simple HTTPS reverse proxy

## Overview
TODO

## Motivation
I wanted HTTPS for `godoc -http :6060`.

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

## Demo
*nix:
```
# generate self-signed certificate and private key
openssl req -newkey rsa:4096 -nodes -keyout key.pem -x509 -days 365 -out cert.pem -subj "/CN=localhost"

# start godoc
godoc -http localhost:6060 &

# secure it
secure -key key.pem -cert cert.pem http://localhost:6060
```

Windows (PowerShell)
```
# somehow obtain key.pem and cert.pem

# start godoc
# Command Prompt: start godoc -http localhost:6060
Start-Process godoc "-http localhost:6060"

# secure it
secure -key key.pem -cert cert.pem http://localhost:6060
```

## Features
- [x] TLS termination proxy
- [ ] Redirect HTTP to HTTPS
