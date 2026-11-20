"""behave environment for the official CAMARA Test_definitions (QoD r4.3 + QoSProfiles r1.2), run UNCHANGED.
Target: Lintas5G qod-adapter 0.1.3 with the mock backend (synthetic devices $MOCK_DEVICE_NET.x), started by ../run-behave.sh.
env: QOD_BASE (adapter URL), QOD_SINK_URL (https sink), QOD_SINK_LOG (sink JSONL)."""
import os, httpx
def before_all(ctx):
    ctx.base = os.environ.get("QOD_BASE", "http://127.0.0.1:18080")
    ctx.sink_url = os.environ.get("QOD_SINK_URL", "https://127.0.0.1:18443/sink")
    ctx.sink_log = os.environ.get("QOD_SINK_LOG", "/tmp/qod-conf/sink.jsonl")
    ctx.http = httpx.Client(base_url=ctx.base, timeout=10)
    ctx.tokens = {}
def before_scenario(ctx, scenario):
    from steps import camara
    camara.reset(ctx, scenario)
def after_scenario(ctx, scenario):
    from steps import camara
    camara.cleanup(ctx)
