"""Synthetic 3-tap fan-in pcap (VLAN 105 ue / 102 n3 / 109 n6) with 5 QUIC packets + 5 MGLT v2.1 probes (UDP 9001).
usage: gen-probe-pcap.py OUT.pcap"""
import struct, hashlib, sys, time
import os
HERE=os.path.dirname(os.path.abspath(__file__))
import importlib.util
sp=importlib.util.spec_from_file_location('m',os.path.join(HERE,'..','zeek','pktlat-mirror.py')); m=importlib.util.module_from_spec(sp); sp.loader.exec_module(m)
def ck(b):
    s=sum(struct.unpack('!%dH'%(len(b)//2),b)); s=(s&0xffff)+(s>>16); s=(s&0xffff)+(s>>16); return (~s)&0xffff
def ip4(src,dst,sp_,dp,payload):
    u=struct.pack('!HHHH',sp_,dp,8+len(payload),0)+payload
    h=struct.pack('!BBHHHBBH4s4s',0x45,0,20+len(u),1,0,64,17,0,bytes(map(int,src.split('.'))),bytes(map(int,dst.split('.'))))
    h=h[:10]+struct.pack('!H',ck(h))+h[12:]
    return h+u
def crc32c(d):
    c=0xffffffff
    for b in d:
        c^=b
        for _ in range(8): c=(c>>1)^(0x82F63B78 if c&1 else 0)
    return c^0xffffffff
def probe(fid,pseq,tns,recs,src=(('10.111.0.2'),5555),dst=('10.99.9.20',9001)):
    b=bytearray(52); b[0:4]=b'MGLT'; b[4]=2; b[5]=2; b[6:8]=struct.pack('!H',52)
    b[8:12]=struct.pack('!I',fid); b[12:16]=struct.pack('!I',pseq); b[16:24]=struct.pack('!Q',tns); b[24:32]=struct.pack('!Q',tns)
    b[32]=17; b[33]=len(recs); b[34]=20
    b[36:40]=bytes(map(int,src[0].split('.'))); b[40:42]=struct.pack('!H',src[1]); b[42:46]=bytes(map(int,dst[0].split('.'))); b[46:48]=struct.pack('!H',dst[1])
    b[48:52]=struct.pack('!I',crc32c(bytes(b[:48])))
    for typ,h,ln,t in recs: b+=bytes([typ,0])+struct.pack('!H',ln)+h+struct.pack('!Q',t)
    return bytes(b)
def eth(ipb): return b'\x00'*12+b'\x08\x00'+ipb
T0=1795016000.0
frames=[]
def add(t,f): frames.append((t,f))
for i in range(5):
    q=bytes([0xc0+i])+bytes(range(60))
    h=hashlib.md5(q[:64]).digest()[:8]
    t=T0+i*0.1
    tns=int(t*1e9)
    ipq=ip4('10.45.0.3','142.250.1.1',50000,443,q)
    # UE tap (raw ip), n3 (eth+gtp), n6 raw ip
    add(t+0.001,m.encapsulate(ipq,'ue'))
    gtp=b'\x30\xff'+struct.pack('!HI',len(ipq),0x1234)+ipq
    outer=ip4('127.0.0.1','127.0.0.2',2152,2152,gtp)
    add(t+0.003,m.encapsulate(eth(outer),'n3'))
    add(t+0.005,m.encapsulate(ipq,'n6'))
    pr=probe(0xabcd,i,tns,[(1,h,len(q),tns)])
    add(t+0.006,m.encapsulate(ip4('10.45.0.3','10.99.9.20',40000,9001,pr),'n6'))
with open(sys.argv[1],'wb') as f:
    f.write(struct.pack('<IHHiIII',0xa1b2c3d4,2,4,0,0,65535,1))
    for t,fr in frames:
        f.write(struct.pack('<IIII',int(t),int((t%1)*1e6),len(fr),len(fr))); f.write(fr)
print(len(frames))
