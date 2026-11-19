-- Lintas5G Fase 0 closeout: per-packet tap-to-tap latency (pkthash.zeek) in ClickHouse, batch-loaded after each run.
-- pkt_tap   : one row per packet per tap (ue, n3, n6, sgiq), ts = host clock (same VM).
-- pkt_phase : test phases written by the Sesi D runner (cond idle|load|load+qod, rep, time window).
-- v_pkt     : join by (session, dir, hash) -> per-packet segment delays; v_pkt_seg long format; v_pkt_q quantiles + coverage.
--
-- sgi-queue (v0.10.1): n6 is post-HTB for DL and pre-ifb for UL (AF_PACKET on ogstun).
-- sgiq is the complementary point (DL pre-HTB via nft dup / tc mirror; UL post-ifb0 on ifb0 TX).
-- ms_sgi_queue = DL: t_n6 - t_sgiq ; UL: t_sgiq - t_n6.
-- DROP VIEW so a re-load of this file picks up the new column (CREATE VIEW IF NOT EXISTS would keep a stale def).
CREATE DATABASE IF NOT EXISTS poc_latency;
CREATE TABLE IF NOT EXISTS poc_latency.pkt_tap (session LowCardinality(String), run_id LowCardinality(String), tap LowCardinality(String),
  dir LowCardinality(String), proto LowCardinality(String), flow String, h FixedString(16), len UInt16, ts Float64,
  teid Nullable(UInt32), qfi Nullable(UInt8)) ENGINE = MergeTree ORDER BY (session, dir, h, tap, ts);
CREATE TABLE IF NOT EXISTS poc_latency.pkt_phase (session LowCardinality(String), run_id LowCardinality(String), cond LowCardinality(String),
  rep UInt8, t_start Float64, t_end Float64) ENGINE = MergeTree ORDER BY (session, t_start);
-- Optional Zeek conn.log (n6) for per-phase tcp/443 vs udp/443 share.
CREATE TABLE IF NOT EXISTS poc_latency.pkt_conn (session LowCardinality(String), run_id LowCardinality(String),
  ts Float64, proto LowCardinality(String), orig_h String, orig_p UInt16, resp_h String, resp_p UInt16,
  duration Float64, orig_bytes UInt64, resp_bytes UInt64, conn_state String)
  ENGINE = MergeTree ORDER BY (session, ts);
DROP VIEW IF EXISTS poc_latency.v_pkt_cov;
DROP VIEW IF EXISTS poc_latency.v_pkt_q;
DROP VIEW IF EXISTS poc_latency.v_pkt_seg;
DROP VIEW IF EXISTS poc_latency.v_pkt;
CREATE VIEW poc_latency.v_pkt AS
SELECT x.session AS session, ph.run_id AS run_id, if(x.t0 <= ph.t_end, ph.cond, 'other') AS cond, if(x.t0 <= ph.t_end, ph.rep, 0) AS rep,
       x.dir AS dir, x.proto AS proto, x.flow AS flow, x.h AS h, x.len AS len, x.qfi AS qfi, x.t0 AS t0,
       x.c_ue AS c_ue, x.c_n3 AS c_n3, x.c_n6 AS c_n6, x.c_sgiq AS c_sgiq,
       if(x.c_ue > 0 AND x.c_n3 > 0, 1000 * if(x.dir = 'UL', x.t_n3 - x.t_ue, x.t_ue - x.t_n3), NULL) AS ms_radio,
       if(x.c_n3 > 0 AND x.c_n6 > 0, 1000 * if(x.dir = 'UL', x.t_n6 - x.t_n3, x.t_n3 - x.t_n6), NULL) AS ms_core,
       if(x.c_ue > 0 AND x.c_n6 > 0, 1000 * if(x.dir = 'UL', x.t_n6 - x.t_ue, x.t_ue - x.t_n6), NULL) AS ms_total,
       if(x.c_n6 > 0 AND x.c_sgiq > 0, 1000 * if(x.dir = 'UL', x.t_sgiq - x.t_n6, x.t_n6 - x.t_sgiq), NULL) AS ms_sgi_queue
FROM (
  SELECT session, dir, h, any(proto) AS proto, any(flow) AS flow, any(len) AS len, maxIf(qfi, tap = 'n3') AS qfi,
         minIf(ts, tap = 'ue') AS t_ue, minIf(ts, tap = 'n3') AS t_n3, minIf(ts, tap = 'n6') AS t_n6,
         minIf(ts, tap = 'sgiq') AS t_sgiq,
         countIf(tap = 'ue') AS c_ue, countIf(tap = 'n3') AS c_n3, countIf(tap = 'n6') AS c_n6,
         countIf(tap = 'sgiq') AS c_sgiq, min(ts) AS t0
  FROM poc_latency.pkt_tap GROUP BY session, dir, h
) AS x
ASOF LEFT JOIN poc_latency.pkt_phase AS ph ON x.session = ph.session AND x.t0 >= ph.t_start;
CREATE VIEW poc_latency.v_pkt_seg AS
SELECT session, run_id, cond, rep, dir, proto, qfi, t0, seg, ms FROM poc_latency.v_pkt
ARRAY JOIN ['radio', 'core', 'total', 'sgi-queue'] AS seg, [ms_radio, ms_core, ms_total, ms_sgi_queue] AS ms
WHERE ms IS NOT NULL AND ms >= 0 AND ms < 5000;
CREATE VIEW poc_latency.v_pkt_q AS
SELECT session, cond, dir, seg, count() AS n, round(quantileExact(0.5)(ms), 3) AS p50, round(quantileExact(0.99)(ms), 3) AS p99,
       round(max(ms), 3) AS max_ms
FROM poc_latency.v_pkt_seg GROUP BY session, cond, dir, seg;
CREATE VIEW poc_latency.v_pkt_cov AS
SELECT session, cond, dir, count() AS pkts, countIf(c_ue > 0 AND c_n3 > 0 AND c_n6 > 0) AS all_taps,
       round(100 * all_taps / pkts, 2) AS coverage_pct,
       countIf(c_n6 > 0 AND c_sgiq > 0) AS sgiq_pairs,
       round(100 * sgiq_pairs / pkts, 2) AS coverage_sgiq_pct,
       countIf(qfi = 2) AS qfi2_pkts,
       countIf(dir = 'UL' AND c_ue > 0 AND c_n6 = 0) + countIf(dir = 'DL' AND c_n6 > 0 AND c_ue = 0) AS lost_or_miss
FROM poc_latency.v_pkt GROUP BY session, cond, dir;
