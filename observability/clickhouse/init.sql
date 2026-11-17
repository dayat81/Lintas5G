CREATE DATABASE IF NOT EXISTS poc_latency;

-- Latency per paket. source=rt: korelasi waktu nyata Zeek (QUIC).
-- source=offline-tcp: baseline TCP fase 2/2b (analisis offline).
-- Dedupe: ReplacingMergeTree pada (run_id, source, proto, flow, dir, seg, hash, off, len, ts).
-- QUIC memakai hash payload; TCP offline memakai off (offset stream).
CREATE TABLE IF NOT EXISTS poc_latency.pkt_latency
(
    run_id String,
    ts DateTime64(6),
    flow String,
    dir LowCardinality(String),
    seg LowCardinality(String),
    proto LowCardinality(String) DEFAULT '',
    hash String DEFAULT '',
    off UInt64 DEFAULT 0,
    len UInt32 DEFAULT 0,
    one_way_ms Nullable(Float64),
    source LowCardinality(String),
    status LowCardinality(String) DEFAULT '',
    wire String DEFAULT '',
    kind LowCardinality(String) DEFAULT '',
    ingested_at DateTime64(3) DEFAULT now64(3)
)
ENGINE = ReplacingMergeTree(ingested_at)
ORDER BY (run_id, source, proto, flow, dir, seg, hash, off, len, ts)
TTL toDateTime(ts) + INTERVAL 60 DAY;

CREATE TABLE IF NOT EXISTS poc_latency.mglt_markers
(
    run_id String,
    ts DateTime64(6),
    t_ue DateTime64(6),
    flow String,
    seq UInt32 DEFAULT 0,
    dir LowCardinality(String),
    seg LowCardinality(String),
    one_way_ms Nullable(Float64),
    evt LowCardinality(String) DEFAULT '',
    orig_dst String DEFAULT '',
    orig_dport UInt32 DEFAULT 0,
    teid UInt64 DEFAULT 0,
    source LowCardinality(String) DEFAULT 'offline-tcp',
    ingested_at DateTime64(3) DEFAULT now64(3)
)
ENGINE = ReplacingMergeTree(ingested_at)
ORDER BY (run_id, flow, seq, dir, seg, ts)
TTL toDateTime(ts) + INTERVAL 60 DAY;

CREATE TABLE IF NOT EXISTS poc_latency.pktlat_stats
(
    run_id String,
    ts DateTime64(6),
    flows UInt64 DEFAULT 0,
    segs UInt64 DEFAULT 0,
    mapped UInt64 DEFAULT 0,
    pending UInt64 DEFAULT 0,
    probes UInt64 DEFAULT 0,
    probe_bytes UInt64 DEFAULT 0,
    probe_dup UInt64 DEFAULT 0,
    crc_bad UInt64 DEFAULT 0,
    recs UInt64 DEFAULT 0,
    rec_dup UInt64 DEFAULT 0,
    rec_resend_used UInt64 DEFAULT 0,
    ul_ok UInt64 DEFAULT 0,
    ul_miss UInt64 DEFAULT 0,
    dl_ok UInt64 DEFAULT 0,
    dl_miss UInt64 DEFAULT 0,
    dl_unmatched_evicted UInt64 DEFAULT 0,
    nomap UInt64 DEFAULT 0,
    flow_drop UInt64 DEFAULT 0,
    evicted UInt64 DEFAULT 0,
    seg_drop UInt64 DEFAULT 0,
    mem_mb Float64 DEFAULT 0,
    source LowCardinality(String) DEFAULT 'rt',
    extra String DEFAULT '',
    ingested_at DateTime64(3) DEFAULT now64(3)
)
ENGINE = ReplacingMergeTree(ingested_at)
ORDER BY (run_id, ts)
TTL toDateTime(ts) + INTERVAL 60 DAY;
