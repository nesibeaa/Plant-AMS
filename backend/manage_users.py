#!/usr/bin/env python3
"""Kullanıcı yönetim scripti - kullanıcıları listele ve ekle"""
import sys
from pathlib import Path

# Backend dizinini path'e ekle
backend_dir = Path(__file__).parent
sys.path.insert(0, str(backend_dir))

from sqlmodel import SQLModel, create_engine, Session, select
from datetime import datetime, timezone
import bcrypt
from typing import Optional
from sqlmodel import Field

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

print("=" * 60)
print("KULLANICI YÖNETİMİ")
print("=" * 60)

with Session(engine) as s:
    # Mevcut kullanıcıları listele
    users = s.exec(select(UserDB)).all()
    print(f"\nToplam kullanıcı sayısı: {len(users)}\n")
    
    if users:
        print("Mevcut kullanıcılar:")
        print("-" * 60)
        for user in users:
            print(f"  ID: {user.id}")
            print(f"  Email: {user.email}")
            print(f"  Username: {user.username}")
            print(f"  Full Name: {user.full_name or 'N/A'}")
            print(f"  Active: {user.is_active}")
            print(f"  Created: {user.created_at}")
            print("-" * 60)
    else:
        print("Henüz kullanıcı yok.\n")
    
    # Komut satırı argümanları kontrol et
    if len(sys.argv) > 1 and sys.argv[1] == "add":
        if len(sys.argv) < 5:
            print("\nHata: Eksik parametreler!")
            print("Kullanım: python3 manage_users.py add <email> <username> <password>")
            sys.exit(1)
        
        email = sys.argv[2]
        username = sys.argv[3]
        password = sys.argv[4]
        
        # Email kontrolü
        existing_email = s.exec(select(UserDB).where(UserDB.email == email)).first()
        if existing_email:
            print(f"\nHata: Bu email zaten kayıtlı: {email}")
            sys.exit(1)
        
        # Username kontrolü
        existing_username = s.exec(select(UserDB).where(UserDB.username == username)).first()
        if existing_username:
            print(f"\nHata: Bu kullanıcı adı zaten alınmış: {username}")
            sys.exit(1)
        
        # Yeni kullanıcı oluştur
        hashed_password = get_password_hash(password)
        new_user = UserDB(
            email=email,
            username=username,
            hashed_password=hashed_password,
            is_active=True
        )
        s.add(new_user)
        s.commit()
        print(f"\n✅ Kullanıcı başarıyla oluşturuldu!")
        print(f"   Email: {email}")
        print(f"   Username: {username}")
    else:
        print("\nYeni kullanıcı eklemek için:")
        print("  python3 manage_users.py add <email> <username> <password>")
        print("\nÖrnek:")
        print("  python3 manage_users.py add user@example.com myuser mypassword123")

