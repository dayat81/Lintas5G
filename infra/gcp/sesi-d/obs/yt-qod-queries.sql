-- YouTube + QoD + MGLT v2.1 (batch, after pkt_latency + pkt_phase load).
-- Lab tap labels: pktlat2 seg s1u = N3, s5s8 = UE tap (NOT S5/S8), sgi = N6.
-- Join window: pkt_latency.ts inside pkt_phase [t_start, t_end] for the same run_id/session.
-- USULAN only: these queries do not declare a verdict by themselves.

-- 1) Per-phase one-way (app <-> tap) p50/p99 + coverage
SELECT
  p.cond, p.rep, l.dir,
  if(l.seg = 's1u', 'n3', if(l.seg = 's5s8', 'ue', if(l.seg = 'sgi', 'n6', l.seg))) AS lab_seg,
  count() AS n,
  countIf(l.status = 'ok' OR l.one_way_ms IS NOT NULL) AS n_ok,
  round(quantileExact(0.50)(l.one_way_ms), 3) AS p50,
  round(quantileExact(0.99)(l.one_way_ms), 3) AS p99,
  round(max(l.one_way_ms), 3) AS max_ms
FROM poc_latency.pkt_latency AS l
INNER JOIN poc_latency.pkt_phase AS p
  ON l.run_id = p.run_id AND toUnixTimestamp64Milli(l.ts)/1000.0 >= p.t_start
                       AND toUnixTimestamp64Milli(l.ts)/1000.0 <= p.t_end
WHERE l.source = 'rt' AND l.proto = 'quic'
GROUP BY p.cond, p.rep, l.dir, lab_seg
ORDER BY p.cond, p.rep, l.dir, lab_seg;

-- 2) Throughput per phase from matched packet lengths (payload only)
SELECT
  p.cond, p.rep, l.dir,
  sum(l.len) AS bytes,
  round(8 * sum(l.len) / greatest(p.t_end - p.t_start, 0.001) / 1e6, 3) AS mbit_s
FROM poc_latency.pkt_latency AS l
INNER JOIN poc_latency.pkt_phase AS p
  ON l.run_id = p.run_id AND toUnixTimestamp64Milli(l.ts)/1000.0 >= p.t_start
                       AND toUnixTimestamp64Milli(l.ts)/1000.0 <= p.t_end
WHERE l.source = 'rt'
GROUP BY p.cond, p.rep, l.dir, p.t_start, p.t_end
ORDER BY p.cond, p.rep, l.dir;

-- 3) Derived RTT proxy (UL+DL one-way on the same tap, same phase; not a true RTT)
SELECT
  cond, rep, lab_seg,
  round(ul_p50 + dl_p50, 3) AS rtt_proxy_p50,
  round(ul_p99 + dl_p99, 3) AS rtt_proxy_p99
FROM (
  SELECT
    p.cond, p.rep,
    if(l.seg = 's1u', 'n3', if(l.seg = 's5s8', 'ue', if(l.seg = 'sgi', 'n6', l.seg))) AS lab_seg,
    quantileExact(0.50)(if(l.dir = 'UL', l.one_way_ms, NULL)) AS ul_p50,
    quantileExact(0.99)(if(l.dir = 'UL', l.one_way_ms, NULL)) AS ul_p99,
    quantileExact(0.50)(if(l.dir = 'DL', l.one_way_ms, NULL)) AS dl_p50,
    quantileExact(0.99)(if(l.dir = 'DL', l.one_way_ms, NULL)) AS dl_p99
  FROM poc_latency.pkt_latency AS l
  INNER JOIN poc_latency.pkt_phase AS p
    ON l.run_id = p.run_id AND toUnixTimestamp64Milli(l.ts)/1000.0 >= p.t_start
                         AND toUnixTimestamp64Milli(l.ts)/1000.0 <= p.t_end
  WHERE l.source = 'rt' AND l.proto = 'quic'
  GROUP BY p.cond, p.rep, lab_seg
);

-- 4) pkthash tap-to-tap (Sesi D v_pkt) restricted to googlevideo-ish flows if a filter table exists.
--    Without DNS/SNI, use proto=quic and the phase window only (same as Sesi D v_pkt_q).
-- SELECT * FROM poc_latency.v_pkt_q WHERE session = '<session>' ORDER BY dir, seg, cond;

-- 5) Probe overhead from pktlat_stats (probe_bytes vs later analysis of UL payload)
SELECT run_id, ts, probes, probe_bytes, recs, rec_resend_used, q_ul_ok, q_dl_ok, q_miss, q_drop, mem_mb
FROM poc_latency.pktlat_stats
ORDER BY ts;

-- 6) sgi-queue (pkthash v_pkt): shaper delay. DL = t_n6 - t_sgiq (post - pre HTB);
--    UL = t_sgiq - t_n6 (post-ifb0 - pre-ifb). See zeek-taps.sh for placement reasoning.
SELECT session, cond, dir, n, p50, p99, max_ms
FROM poc_latency.v_pkt_q
WHERE seg = 'sgi-queue'
ORDER BY cond, dir;

-- 7) Per-phase transport share from Zeek conn.log (n6), port 443 only.
--    Overlap: conn interval [ts, ts+duration] intersects the phase window.
SELECT
  p.cond, p.rep,
  countIf(c.proto = 'udp' AND (c.resp_p = 443 OR c.orig_p = 443)) AS udp443_conns,
  countIf(c.proto = 'tcp' AND (c.resp_p = 443 OR c.orig_p = 443)) AS tcp443_conns,
  sumIf(c.orig_bytes + c.resp_bytes, c.proto = 'udp' AND (c.resp_p = 443 OR c.orig_p = 443)) AS udp443_bytes,
  sumIf(c.orig_bytes + c.resp_bytes, c.proto = 'tcp' AND (c.resp_p = 443 OR c.orig_p = 443)) AS tcp443_bytes
FROM poc_latency.pkt_conn AS c
INNER JOIN poc_latency.pkt_phase AS p
  ON c.session = p.session
 AND c.ts <= p.t_end
 AND (c.ts + if(c.duration > 0, c.duration, 0)) >= p.t_start
GROUP BY p.cond, p.rep
ORDER BY p.cond, p.rep;
