"""Entry point for PyInstaller — single binary server."""
import uvicorn
import structlog
from runtime.models.config import get_config

def main():
    config = get_config()
    config.log_dir.mkdir(parents=True, exist_ok=True)
    structlog.configure(
        processors=[
            structlog.processors.TimeStamper(fmt="iso"),
            structlog.processors.JSONRenderer(),
        ],
    )
    uvicorn.run("apps.desktop.server:app", host=config.host, port=config.port, log_level="info")

if __name__ == "__main__":
    main()
