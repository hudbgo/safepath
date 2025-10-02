# backend/app/crud.py
from sqlalchemy.orm import Session
from . import models, schemas

def create_finding(db: Session, finding: schemas.FindingCreate):
    db_f = models.Finding(**finding.dict())
    db.add(db_f)
    db.commit()
    db.refresh(db_f)
    return db_f

def list_findings(db: Session, skip: int = 0, limit: int = 100):
    return db.query(models.Finding).order_by(models.Finding.created_at.desc()).offset(skip).limit(limit).all()

def get_findings_by_host(db: Session, host: str):
    return db.query(models.Finding).filter(models.Finding.host == host).order_by(models.Finding.created_at.desc()).all()
