BINARY=dist/rmake-proxy
INSTALLER=dist/installer.sh
.PHONY: clean
all: $(INSTALLER)

$(BINARY): version.go
	GOARCH=arm GOARM=7 go build -ldflags="-w -s" -o $(BINARY) 
version.go: 
	go generate

$(INSTALLER): $(BINARY) scripts/installer.sh
	cp scripts/installer.sh $@
	gzip -c $(BINARY) >> $@
	chmod +x $@
clean:
	rm -fr dist
