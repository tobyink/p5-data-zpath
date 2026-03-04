#!/bin/sh

cpanm --version || ( curl -L https://cpanmin.us | perl - App::cpanminus )
cpanm -n XML::LibXML Test2::V0 App::Prove
prove -lrv t
