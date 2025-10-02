# backend/app/routers.py
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from . import schemas, crud
from .db import SessionLocal

router = APIRouter(prefix="/api")

# dependency
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

@router.get("/health")
def health():
    return {"status": "ok"}

@router.post("/findings", response_model=schemas.FindingOut)
def post_finding(f: schemas.FindingCreate, db: Session = Depends(get_db)):
    return crud.create_finding(db, f)

@router.get("/findings", response_model=list[schemas.FindingOut])
def get_findings(skip: int = 0, limit: int = 100, db: Session = Depends(get_db)):
    return crud.list_findings(db, skip=skip, limit=limit)

@router.get("/findings/host/{host}", response_model=list[schemas.FindingOut])
def findings_by_host(host: str, db: Session = Depends(get_db)):
    return crud.get_findings_by_host(db, host)
