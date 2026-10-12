from sqlalchemy import text


def test_service_info_reports_message_version_and_pod(client):
    response = client.get("/")
    assert response.status_code == 200
    assert response.json() == {
        "service": "notes-api",
        "message": "hello from tests",
        "version": "test",
        "pod": "test-pod",
    }
    assert response.headers["X-Pod-Name"] == "test-pod"
    assert response.headers["X-Request-ID"]


def test_request_id_is_propagated(client):
    response = client.get("/healthz", headers={"X-Request-ID": "abc123"})
    assert response.headers["X-Request-ID"] == "abc123"


def test_liveness(client):
    assert client.get("/healthz").json() == {"status": "ok"}


def test_readiness_ok_when_database_reachable(client):
    response = client.get("/readyz")
    assert response.status_code == 200
    assert response.json()["database"] == "ok"


def test_readiness_fails_when_database_unreachable(client):
    client.app.state.engine.dispose()

    def broken_session():
        class Broken:
            def __enter__(self):
                return self

            def __exit__(self, *exc):
                return False

            def execute(self, *args, **kwargs):
                raise RuntimeError("db down")

        return Broken()

    client.app.state.session_factory = broken_session
    response = client.get("/readyz")
    assert response.status_code == 503
    assert response.json()["database"] == "unreachable"


def test_crud_lifecycle(client):
    created = client.post("/notes", json={"title": "first", "content": "hello"})
    assert created.status_code == 201
    note = created.json()
    assert note["title"] == "first"

    assert client.get(f"/notes/{note['id']}").json()["content"] == "hello"
    assert [n["id"] for n in client.get("/notes").json()] == [note["id"]]

    updated = client.patch(f"/notes/{note['id']}", json={"content": "changed"})
    assert updated.status_code == 200
    assert updated.json()["title"] == "first"
    assert updated.json()["content"] == "changed"

    assert client.delete(f"/notes/{note['id']}").status_code == 204
    assert client.get(f"/notes/{note['id']}").status_code == 404


def test_validation_rejects_empty_title(client):
    assert client.post("/notes", json={"title": ""}).status_code == 422


def test_missing_note_returns_404(client):
    assert client.get("/notes/999").status_code == 404
    assert client.patch("/notes/999", json={"title": "x"}).status_code == 404
    assert client.delete("/notes/999").status_code == 404


def test_pagination_bounds(client):
    for i in range(3):
        client.post("/notes", json={"title": f"n{i}"})
    assert len(client.get("/notes?limit=2").json()) == 2
    assert len(client.get("/notes?limit=2&offset=2").json()) == 1
    assert client.get("/notes?limit=0").status_code == 422
    assert client.get("/notes?limit=101").status_code == 422


def test_metrics_use_route_templates_not_raw_paths(client):
    client.post("/notes", json={"title": "m"})
    client.get("/notes/1")
    body = client.get("/metrics").text
    assert 'handler="/notes/{note_id}"' in body
    assert 'handler="/notes/1"' not in body
    assert "http_request_duration_seconds_bucket" in body


def test_database_is_queryable(client):
    with client.app.state.session_factory() as session:
        assert session.execute(text("SELECT 1")).scalar() == 1
