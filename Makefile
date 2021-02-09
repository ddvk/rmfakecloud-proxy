.PHONY: clean
build: version.go
	go build
version.go: 
	go generate
clean:
	rm secure
