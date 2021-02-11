BINARY=dist/rmake-proxy
INSTALLER=dist/installer.sh
.PHONY: clean
all: $(INSTALLER)

$(BINARY): version.go
	GOARCH=arm go build -ldflags="-w -s" -trimpath -o $(BINARY) 
version.go: 
	go generate

$(INSTALLER): $(BINARY) scripts/installer.sh
	cp scripts/install.sh $@
	gzip -c $(BINARY) >> $@
clean:
	rm -fr dist
