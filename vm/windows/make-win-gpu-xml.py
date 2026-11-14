#!/usr/bin/env python3
"""Derive a GPU-passthrough Windows domain XML from an existing Windows VM dump.
usage: make-win-gpu-xml.py in.xml out.xml [new-name] [gpu-bus-hex]"""
import re, sys, uuid
src, dst = sys.argv[1], sys.argv[2]
name = sys.argv[3] if len(sys.argv) > 3 else "win10-gpu"
bus = sys.argv[4] if len(sys.argv) > 4 else "0x12"
s = open(src).read()
s = re.sub(r"<name>.*?</name>", f"<name>{name}</name>", s, count=1)
s = re.sub(r"<uuid>.*?</uuid>", f"<uuid>{uuid.uuid4()}</uuid>", s, count=1)
s = re.sub(r"<mac address='[^']*'/>", "<mac address='52:54:00:16:38:43'/>", s)
s = re.sub(r"port='5900' autoport='no'", "port='5903' autoport='no'", s)
hd = ""
for f in (0, 1):
    hd += ("<hostdev mode='subsystem' type='pci' managed='no'><source>"
           f"<address domain='0x0000' bus='{bus}' slot='0x00' function='0x{f}'/>"
           "</source></hostdev>\n")
s = s.replace("</devices>", hd + "</devices>")
open(dst, "w").write(s)
