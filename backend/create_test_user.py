#!/usr/bin/env python3
"""Test kullanıcısı oluşturma scripti"""
import sys
import os
from pathlib import Path

# Backend dizinini path'e ekle
backend_dir = Path(__file__).parent
sys.path.insert(0, str(backend_dir))

from sqlmodel import SQLModel, create_engine, Session, select
from datetime import datetime, timezone
import bcrypt

# UserDB modeli (main.py'den kopyala)
from sqlmodel import Field
from typing import Optional

class UserDB(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    email: str = Field(unique=True, index=True)
    username: str = Field(unique=True, index=True)
    hashed_password: str
    full_name: Optional[str] = None
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    is_active: bool = True

def get_password_hash(password: str) -> str:
    """Şifreyi hash'le - bcrypt direkt kullan"""
    password_bytes = password.encode('utf-8')
    if len(password_bytes) > 72:
        password_bytes = password_bytes[:72]
    salt = bcrypt.gensalt()
    hashed = bcrypt.hashpw(password_bytes, salt)
    return hashed.decode('utf-8')

# Veritabanı bağlantısı
db_path = backend_dir / "app.db"
engine = create_engine(f"sqlite:///{db_path}", echo=False, connect_args={"check_same_thread": False})

# Tabloları oluştur
SQLModel.metadata.create_all(engine)

# Test kullanıcısı oluştur
with Session(engine) as s:
    # Mevcut kullanıcıyı kontrol et
    existing = s.exec(select(UserDB).where(UserDB.email == "test@example.com")).first()
    
    if existing:
        print("Test kullanıcısı zaten mevcut!")
        print(f"Email: {existing.email}")
        print(f"Username: {existing.username}")
    else:
        # Yeni kullanıcı oluştur
        hashed_password = get_password_hash("test123")
        new_user = UserDB(
            email="test@example.com",
            username="testuser",
            hashed_password=hashed_password,
            is_active=True
        )
        s.add(new_user)
        s.commit()
        print("Test kullanıcısı oluşturuldu!")
        print("Email: test@example.com")
        print("Şifre: test123")
        print("Username: testuser")

