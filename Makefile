BINARY=dist/rmfakecloud-proxy
WINBINARY=dist/rmfakecloud-proxy.exe
LINUXBINARY=dist/rmfakecloud-proxy64
INSTALLER=dist/installer.sh
.PHONY: clean
all: $(INSTALLER) $(WINBINARY) $(LINUXBINARY)

$(LINUXBINARY): version.go main.go
	go build -ldflags="-w -s" -o $@

$(BINARY): version.go main.go
	GOARCH=arm GOARM=7 go build -ldflags="-w -s" -o $@

$(WINBINARY): version.go main.go
	GOOS=windows go build -ldflags="-w -s" -o $@

version.go:
	go generate

$(INSTALLER): $(BINARY) scripts/installer.sh
	cp scripts/installer.sh $@
	gzip -c $(BINARY) >> $@
	chmod +x $@
clean:
	rm -fr dist
