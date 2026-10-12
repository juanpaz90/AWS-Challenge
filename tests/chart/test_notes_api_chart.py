"""Behavioural tests for charts/notes-api: render with `helm template` and assert on the output.

Run: task chart:test   (uv run --no-project --with pytest --with pyyaml pytest tests/chart)
"""

import subprocess
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).resolve().parents[2]
CHART = ROOT / "charts" / "notes-api"
CI_VALUES = CHART / "ci" / "validate-values.yaml"


def render(env: str = "local", *sets: str, check: bool = True) -> subprocess.CompletedProcess:
    cmd = ["helm", "template", "notes-api", str(CHART), "--namespace", "notes",
           "-f", str(CHART / "values.yaml"), "-f", str(CHART / f"values-{env}.yaml"),
           "-f", str(CI_VALUES)]
    for s in sets:
        cmd += ["--set", s]
    return subprocess.run(cmd, capture_output=True, text=True, check=check)


def docs(env: str = "local", *sets: str) -> list[dict]:
    return [d for d in yaml.safe_load_all(render(env, *sets).stdout) if d]


def one(objs: list[dict], kind: str, name: str | None = None) -> dict:
    found = [o for o in objs if o["kind"] == kind and (name is None or o["metadata"]["name"] == name)]
    assert len(found) == 1, f"expected one {kind} {name or ''}, got {len(found)}"
    return found[0]


@pytest.fixture(scope="module")
def local() -> list[dict]:
    return docs("local")


# --- security ---------------------------------------------------------------------------------

@pytest.mark.parametrize("env", ["local", "dev", "prod"])
def test_no_secret_objects_or_credentials_rendered(env):
    objs = docs(env)
    assert not [o for o in objs if o["kind"] == "Secret"]
    out = render(env).stdout.lower()
    assert "password:" not in out.replace("db_password", "")


def test_pods_meet_restricted_pod_security(local):
    for kind in ("Deployment", "Job"):
        spec = one(local, kind)["spec"]["template"]["spec"]
        assert spec["securityContext"]["runAsNonRoot"] is True
        assert spec["securityContext"]["seccompProfile"]["type"] == "RuntimeDefault"
        assert spec["automountServiceAccountToken"] is False
        for c in spec["containers"]:
            sc = c["securityContext"]
            assert sc["allowPrivilegeEscalation"] is False
            assert sc["readOnlyRootFilesystem"] is True
            assert sc["capabilities"]["drop"] == ["ALL"]
            assert c["resources"]["requests"] and c["resources"]["limits"]["memory"]


def test_database_credentials_come_from_secret_reference(local):
    env = {e["name"]: e for e in one(local, "Deployment")["spec"]["template"]["spec"]["containers"][0]["env"]}
    for var, key in [("DB_HOST", "host"), ("DB_PORT", "port"), ("DB_NAME", "dbname"),
                     ("DB_USER", "username"), ("DB_PASSWORD", "password")]:
        ref = env[var]["valueFrom"]["secretKeyRef"]
        assert ref == {"name": "notes-db-app", "key": key}


def test_service_is_cluster_ip_only(local):
    assert one(local, "Service")["spec"]["type"] == "ClusterIP"


# --- availability -----------------------------------------------------------------------------

def test_deployment_has_all_probes_and_zero_downtime_rollout(local):
    dep = one(local, "Deployment")
    c = dep["spec"]["template"]["spec"]["containers"][0]
    assert c["startupProbe"]["httpGet"]["path"] == "/healthz"
    assert c["livenessProbe"]["httpGet"]["path"] == "/healthz"
    assert c["readinessProbe"]["httpGet"]["path"] == "/readyz"
    assert c["lifecycle"]["preStop"]["sleep"]["seconds"] > 0
    assert dep["spec"]["strategy"]["rollingUpdate"]["maxUnavailable"] == 0
    assert "replicas" not in dep["spec"], "the HPA owns the replica count"


def test_topology_spread_honours_taints(local):
    tsc = one(local, "Deployment")["spec"]["template"]["spec"]["topologySpreadConstraints"]
    assert tsc[0]["topologyKey"] == "kubernetes.io/hostname"
    assert tsc[0]["nodeTaintsPolicy"] == "Honor"


def test_prod_spreads_hard_across_zones():
    tsc = one(docs("prod"), "Deployment")["spec"]["template"]["spec"]["topologySpreadConstraints"]
    zone = [t for t in tsc if t["topologyKey"] == "topology.kubernetes.io/zone"][0]
    assert zone["whenUnsatisfiable"] == "DoNotSchedule"


def test_hpa_and_pdb(local):
    hpa = one(local, "HorizontalPodAutoscaler")["spec"]
    assert (hpa["minReplicas"], hpa["maxReplicas"]) == (2, 4)
    pdb = one(local, "PodDisruptionBudget")["spec"]
    assert pdb["minAvailable"] == 1
    assert pdb["unhealthyPodEvictionPolicy"] == "AlwaysAllow"


def test_config_change_rolls_pods():
    a = one(docs("local"), "Deployment")["spec"]["template"]["metadata"]["annotations"]["checksum/config"]
    b = one(docs("local", "config.appMessage=changed"), "Deployment")["spec"]["template"]["metadata"]["annotations"]["checksum/config"]
    assert a != b


# --- migrations -------------------------------------------------------------------------------

def test_migration_is_a_pre_install_and_pre_upgrade_hook(local):
    job = one(local, "Job")
    ann = job["metadata"]["annotations"]
    assert ann["helm.sh/hook"] == "pre-install,pre-upgrade"
    assert "before-hook-creation" in ann["helm.sh/hook-delete-policy"]
    c = job["spec"]["template"]["spec"]["containers"][0]
    assert c["command"] == ["alembic", "upgrade", "head"]
    # Hooks run before the release's ConfigMap exists, so the Job must not depend on it.
    assert "envFrom" not in c
    assert "serviceAccountName" not in job["spec"]["template"]["spec"]


# --- networking -------------------------------------------------------------------------------

def test_network_policies(local):
    pols = {o["metadata"]["name"]: o["spec"] for o in local if o["kind"] == "NetworkPolicy"}
    assert set(pols) == {"default-deny-all", "allow-dns-egress", "notes-api-api", "notes-api-migration"}
    assert pols["default-deny-all"] == {"podSelector": {}, "policyTypes": ["Ingress", "Egress"]}

    api = pols["notes-api-api"]
    sources = [f["namespaceSelector"]["matchLabels"]["kubernetes.io/metadata.name"] for f in api["ingress"][0]["from"]]
    assert sources == ["gateway", "monitoring"]
    assert api["ingress"][0]["ports"] == [{"port": 8000, "protocol": "TCP"}]
    assert api["egress"] == [{
        "to": [{"podSelector": {"matchLabels": {"cnpg.io/cluster": "notes-db"}}}],
        "ports": [{"port": 5432, "protocol": "TCP"}],
    }]
    assert "ingress" not in pols["notes-api-migration"], "migration pods accept no traffic"


def test_route_attaches_to_shared_gateway_https(local):
    route = one(local, "HTTPRoute")["spec"]
    assert route["hostnames"] == ["api.localtest.me"]
    assert route["parentRefs"] == [{"name": "platform", "namespace": "gateway", "sectionName": "https"}]


# --- schema guardrails (must be rejected) -----------------------------------------------------

@pytest.mark.parametrize(("sets", "reason"), [
    (["image.tag=latest"], "mutable tag"),
    (["image.tag=", "image.digest="], "no tag or digest"),
    (["database.existingSecret="], "no credentials Secret"),
    (["service.type=NodePort"], "API exposed outside the Gateway"),
    (["service.type=LoadBalancer"], "API exposed outside the Gateway"),
    (["securityContext.readOnlyRootFilesystem=false"], "writable root filesystem"),
    (["podSecurityContext.runAsNonRoot=false"], "root user"),
    (["securityContext.allowPrivilegeEscalation=true"], "privilege escalation"),
    (["config.logLevel=TRACE"], "unknown log level"),
    (["replicaCont=3"], "typo in a top-level key"),
    (["terminationGracePeriodSeconds=10"], "grace period shorter than preStop + drain"),
])
def test_unsafe_values_are_rejected(sets, reason):
    result = render("local", *sets, check=False)
    assert result.returncode != 0, f"accepted {sets} ({reason})"
