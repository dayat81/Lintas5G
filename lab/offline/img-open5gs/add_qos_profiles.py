import sys; p=sys.argv[1]; s=open(p).read()
anchor="""      - address: 127.0.0.13
        port: 9090
"""
prof="""  qos_profiles:     # Lintas5G: CAMARA qos-profiles name -> PCC rule 5QI (qos_index)
    - reference: QOS_E
      qos_index: 80
    - reference: QOS_S
      qos_index: 2
    - reference: QOS_M
      qos_index: 3
    - reference: QOS_L
      qos_index: 4
    - reference: QOS_7
      qos_index: 7
"""
assert s.count(anchor)==1 and 'reference: QOS_E' not in s
open(p,'w').write(s.replace(anchor, anchor+prof))
