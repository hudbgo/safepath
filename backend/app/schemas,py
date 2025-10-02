# backend/app/schemas.py
from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class FindingCreate(BaseModel):
    host: str
    ip: Optional[str] = None
    port: Optional[str] = None
    protocol: Optional[str] = None
    service: Optional[str] = None
    severity: Optional[str] = None
    description: Optional[str] = None
    evidence: Optional[str] = None

class FindingOut(FindingCreate):
    id: int
    created_at: datetime

    class Config:
        orm_mode = True
