#!/usr/bin/make

all: help

help:
	@echo 'Simple make file that runs a bash script, which then runs a makefile... :)'

install:

	./install.sh

clean:
	rm -rf modsec_build/
	rm -rf etc/
	rm -rf usr/
	rm -rf nginx*
	rm -rf ModSecurity-nginx/
