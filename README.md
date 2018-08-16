# secure
Super simple HTTPS reverse proxy

## Overview
TODO

## Motivation
I wanted HTTPS for `godoc -http :6060`.

## Usage
```
secure -key-file path/to/key/file -cert-file path/to/cert/file -upstream http://localhost:6060 -addr :443
```

## Demo
*nix:
```
# generate cert
openssl req -newkey rsa:4096 -nodes -keyout key.pem -x509 -days 365 -out cert.pem -subj "/CN=localhost"

# start godoc
godoc -http localhost:6060 &

# secure it
go run main.go -key-file key.pem -cert-file cert.pem -upstream http://localhost:6060 -addr :443
```

Windows (PowerShell)
```
# somehow obtain key.pem and cert.pem

# start godoc
# cmd: start godoc -http localhost:6060
Start-Process godoc "-http localhost:6060"

# secure it
go run main.go -key-file key.pem -cert-file cert.pem -upstream http://localhost:6060 -addr :443
```

## Features
- [x] TLS termination proxy
- [ ] Redirect HTTP to HTTPS
