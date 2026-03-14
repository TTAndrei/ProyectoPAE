"""Shared pytest fixtures."""
import os
import tempfile
import pytest
from httpx import AsyncClient, ASGITransport

# Set env vars BEFORE importing any app modules
_tmp = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
_TMP_DB = _tmp.name
_tmp.close()
os.environ["DB_PATH"] = _TMP_DB
os.environ["SECRET_KEY"] = "test_secret_key"


@pytest.fixture(scope="session", autouse=True)
def test_db():
    """Initialise the test database once for the whole session."""
    from app.database import init_db
    init_db()
    yield _TMP_DB
    try:
        os.unlink(_TMP_DB)
    except FileNotFoundError:
        pass


@pytest.fixture(scope="session")
def app(test_db):
    from app.main import create_app
    return create_app()


@pytest.fixture
async def client(app):
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
        yield c


@pytest.fixture
async def central_token(client):
    resp = await client.post("/auth/login", json={"username": "central", "password": "central123"})
    return resp.json()["token"]


@pytest.fixture
async def driver1_token(client):
    resp = await client.post("/auth/login", json={"username": "driver1", "password": "driver123"})
    return resp.json()["token"]
