#!/usr/bin/make

install:

	./install.sh

clean:
	rm -rf modsec_build/
	rm -rf etc/
	rm -rf usr/
	rm -rf nginx*
	rm -rf ModSecurity-nginx/
