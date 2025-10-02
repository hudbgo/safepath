# backend/app/models.py
from sqlalchemy import Column, Integer, String, Text, DateTime
from sqlalchemy.sql import func
from .db import Base

class Finding(Base):
    __tablename__ = "findings"
    id = Column(Integer, primary_key=True, index=True)
    host = Column(String(128), index=True)
    ip = Column(String(64), index=True)
    port = Column(String(32))
    protocol = Column(String(16))
    service = Column(String(128))
    severity = Column(String(16))
    description = Column(Text)
    evidence = Column(Text)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
