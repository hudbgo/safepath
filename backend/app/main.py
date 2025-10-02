# backend/app/main.py
import logging
from fastapi import FastAPI
from .routers import router
from .db import Base, engine
import app.models  # noqa: F401 ensure models are loaded for metadata

log = logging.getLogger("safepath.backend")
app = FastAPI(title="safepath - Vulnerability API")
app.include_router(router)

@app.on_event("startup")
def on_startup():
    # Create tables if not exist
    Base.metadata.create_all(bind=engine)
    log.info("DB tables checked/created")
