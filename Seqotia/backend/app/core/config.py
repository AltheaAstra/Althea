import os
from dataclasses import dataclass
from pathlib import Path


def _default_data_dir() -> Path:
    if os.name == "nt":
        return Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData" / "Local")) / "Seqotia"
    return Path.home() / ".local" / "share" / "seqotia"


def _load_backend_env_file() -> None:
    """Load non-empty values from backend/.env without overriding the process env."""
    env_path = Path(__file__).parents[2] / ".env"
    if not env_path.is_file():
        return
    for raw_line in env_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key, value = key.strip(), value.strip().strip("\"'")
        if key and value:
            os.environ.setdefault(key, value)


@dataclass(frozen=True)
class Settings:
    host: str
    port: int
    data_dir: Path
    database_path: Path
    upload_dir: Path
    max_upload_bytes: int
    allow_remote: bool


def get_settings() -> Settings:
    _load_backend_env_file()
    data_dir = Path(os.environ.get("SEQOTIA_DATA_DIR") or _default_data_dir()).expanduser().resolve()
    database_path = Path(os.environ.get("SEQOTIA_DB_PATH") or data_dir / "seqotia.sqlite3").expanduser().resolve()
    upload_dir = Path(os.environ.get("UPLOAD_DIR") or data_dir / "uploads").expanduser().resolve()
    max_mb = int(os.environ.get("MAX_UPLOAD_MB", "25"))
    if max_mb < 1 or max_mb > 250:
        raise ValueError("MAX_UPLOAD_MB must be between 1 and 250.")
    port = int(os.environ.get("APP_PORT", "8000"))
    if port < 1 or port > 65535:
        raise ValueError("APP_PORT must be between 1 and 65535.")
    return Settings(
        host=os.environ.get("APP_HOST", "127.0.0.1"),
        port=port,
        data_dir=data_dir,
        database_path=database_path,
        upload_dir=upload_dir,
        max_upload_bytes=max_mb * 1024 * 1024,
        allow_remote=os.environ.get("SEQOTIA_ALLOW_REMOTE", "0").lower() in {"1", "true", "yes"},
    )
