-- Lintas5G Fase 0 - skema ClickHouse batch (poc_latency). Dimuat setelah tes dari salinan log lokal (bukan real time).
CREATE DATABASE IF NOT EXISTS poc_latency;
CREATE TABLE IF NOT EXISTS poc_latency.probes (session LowCardinality(String), cond LowCardinality(String), rep UInt8,
  metric LowCardinality(String), seq UInt32, value_ms Float64, ok UInt8) ENGINE = MergeTree ORDER BY (session, cond, rep, metric, seq);
CREATE TABLE IF NOT EXISTS poc_latency.adapter (session LowCardinality(String), ts DateTime64(3, 'UTC'), event LowCardinality(String),
  qod_id String, source LowCardinality(String), apply_ms Nullable(Float64), remove_ms Nullable(Float64), reserve_ms Nullable(Float64),
  gbr_kbps Nullable(UInt32)) ENGINE = MergeTree ORDER BY (session, ts);
CREATE TABLE IF NOT EXISTS poc_latency.iperf (session LowCardinality(String), cond LowCardinality(String), rep UInt8,
  dir LowCardinality(String), t_end_s Float64, mbps Float64) ENGINE = MergeTree ORDER BY (session, cond, rep, dir, t_end_s);
CREATE TABLE IF NOT EXISTS poc_latency.zeek_conn (session LowCardinality(String), ifc LowCardinality(String), ts Float64, uid String,
  orig_h String, orig_p UInt16, resp_h String, resp_p UInt16, proto LowCardinality(String), service String, duration Float64,
  orig_bytes UInt64, resp_bytes UInt64, conn_state LowCardinality(String), orig_pkts UInt64, resp_pkts UInt64, tunnel_parents String)
  ENGINE = MergeTree ORDER BY (session, ifc, ts);
CREATE TABLE IF NOT EXISTS poc_latency.zeek_capture_loss (session LowCardinality(String), ifc LowCardinality(String), ts Float64,
  ts_delta Float64, peer String, gaps UInt64, acks UInt64, percent_lost Float64) ENGINE = MergeTree ORDER BY (session, ifc, ts);
CREATE TABLE IF NOT EXISTS poc_latency.zeek_tunnel (session LowCardinality(String), ifc LowCardinality(String), ts Float64, uid String,
  orig_h String, orig_p UInt16, resp_h String, resp_p UInt16, tunnel_type LowCardinality(String), action LowCardinality(String))
  ENGINE = MergeTree ORDER BY (session, ifc, ts);
CREATE TABLE IF NOT EXISTS poc_latency.flow_gbr (session LowCardinality(String), cond LowCardinality(String), proto LowCardinality(String),
  dir LowCardinality(String), target_kbps Float64, goodput_kbps Float64, loss_pct Nullable(Float64)) ENGINE = MergeTree ORDER BY (session, cond, proto, dir);
CREATE VIEW IF NOT EXISTS poc_latency.v_quantiles AS
  SELECT session, cond, metric, count() n, round(quantileExact(0.5)(value_ms),1) p50, round(quantileExact(0.95)(value_ms),1) p95,
         round(quantileExact(0.99)(value_ms),1) p99, round(max(value_ms),1) max_ms
  FROM poc_latency.probes WHERE ok = 1 GROUP BY session, cond, metric;
CREATE VIEW IF NOT EXISTS poc_latency.v_cv AS
  SELECT session, cond, metric, count() reps, round(avg(p50),1) p50_mean, round(100*stddevPop(p50)/avg(p50),1) cv_p50_pct,
         round(avg(p99),1) p99_mean, round(100*stddevPop(p99)/avg(p99),1) cv_p99_pct
  FROM (SELECT session, cond, rep, metric, quantileExact(0.5)(value_ms) p50, quantileExact(0.99)(value_ms) p99
        FROM poc_latency.probes WHERE ok = 1 AND rep > 0 GROUP BY session, cond, rep, metric)
  GROUP BY session, cond, metric;
