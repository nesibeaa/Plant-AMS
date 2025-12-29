# backend/main.py
from fastapi import FastAPI, UploadFile, File, HTTPException, Depends, status
from fastapi.responses import Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel, field_validator, EmailStr
from typing import Optional, Deque, Dict, List, Literal, Any
from pathlib import Path
from collections import deque
from datetime import datetime, timezone
from datetime import timedelta
from sqlalchemy import text as sqltext
from sqlalchemy import func, event
import io
import os
import secrets
from PIL import Image
import numpy as np
from jose import JWTError, jwt
from passlib.context import CryptContext
import bcrypt
from dotenv import load_dotenv
from pathlib import Path
import httpx

# .env dosyasını yükle (backend dizininden)
env_path = Path(__file__).parent / ".env"
load_dotenv(dotenv_path=env_path)

from plant_classifier import PlantClassifier
from plantvillage_classifier import PlantVillageClassifier


from sqlmodel import SQLModel, Field, create_engine, Session, select

app = FastAPI(title="AA Backend", version="0.5.0")

# ----------------- Exception Handler -----------------
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import ValidationError

@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request, exc):
    import traceback
    error_msg = f"Validation Error: {str(exc)}\n{traceback.format_exc()}"
    print(error_msg)
    return JSONResponse(
        status_code=200,  # simulate.py için 200 dön
        content={"ok": False, "error": "Validation error", "details": str(exc)}
    )

@app.exception_handler(Exception)
async def global_exception_handler(request, exc):
    import traceback
    error_msg = f"Error: {type(exc).__name__}: {str(exc)}\n{traceback.format_exc()}"
    print(error_msg)
    return JSONResponse(
        status_code=200,  # simulate.py için 200 dön
        content={"ok": False, "error": str(exc), "type": type(exc).__name__}
    )

# ----------------- NO-CACHE (UI her zaman taze veri görsün) -----------------
@app.middleware("http")
async def add_no_cache_headers(request, call_next):
    resp: Response = await call_next(request)
    resp.headers["Cache-Control"] = "no-store"
    return resp

# ----------------- CORS ------------------------------------------------------
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],   # demo için açık
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ----------------- ZAMAN YARDIMCILARI (UTC + Z sonekli) ---------------------
def utcnow() -> datetime:
    return datetime.now(timezone.utc)

def to_utc(dt: Optional[datetime]) -> datetime:
    """None ise now(UTC). Naive ise UTC varsay. Aware ise UTC'ye çevir."""
    if dt is None:
        return utcnow()
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)

def iso_z(dt: datetime) -> str:
    """ISO 8601 + Z (örn. 2025-10-19T19:45:12.345Z)."""
    return dt.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")

# ----------------- DB --------------------------------------------------------
# SQLite için thread-safe ve WAL mode ayarları
engine = create_engine(
    "sqlite:///./app.db",
    echo=False,
    connect_args={
        "check_same_thread": False,  # Thread-safe
        "timeout": 20.0,  # Connection timeout (saniye)
    },
    pool_pre_ping=True,  # Bağlantı sağlığını kontrol et
    pool_size=10,  # Connection pool size
    max_overflow=20,  # Max overflow connections
)
# SQLite WAL mode'u etkinleştir (aynı anda okuma/yazma)
@event.listens_for(engine, "connect")
def set_sqlite_pragma(dbapi_conn, connection_record):
    cursor = dbapi_conn.cursor()
    cursor.execute("PRAGMA journal_mode=WAL")
    cursor.execute("PRAGMA synchronous=NORMAL")
    cursor.execute("PRAGMA busy_timeout=30000")  # 30 saniye busy timeout
    cursor.execute("PRAGMA foreign_keys=ON")
    cursor.close()

class ReadingDB(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    sensor_id: str
    type: str
    value: float
    ts: datetime  # timezone-aware datetime yazacağız

class ActuatorEventDB(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    device: str            # "fan" | "heater" | "humidifier"
    action: str            # "on" | "off" | "auto"
    reason: str            # "manual" | "automation"
    mode: str              # o andaki mode (auto/manual)
    state: str             # o andaki state (on/off)
    ts: datetime


class AlertDB(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    level: str
    source: str
    message: str
    ts: datetime  # timezone-aware datetime yazacağız

class UserDB(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    email: str = Field(unique=True, index=True)
    username: str = Field(unique=True, index=True)
    hashed_password: str
    full_name: Optional[str] = None
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    is_active: bool = True

@app.on_event("startup")
def on_startup():
    SQLModel.metadata.create_all(engine)

# ----------------- AUTHENTICATION -------------------------------------------
# SECRET_KEY environment variable'dan al, yoksa güvenli bir key oluştur (sadece development için)
SECRET_KEY = os.getenv("SECRET_KEY")
if not SECRET_KEY:
    # Development modunda: otomatik güvenli key oluştur (her restart'ta değişir)
    # Production'da MUTLAKA environment variable kullan!
    SECRET_KEY = secrets.token_urlsafe(32)
    print("⚠️  WARNING: SECRET_KEY environment variable bulunamadı!")
    print("⚠️  Development modunda otomatik key oluşturuldu (her restart'ta değişir)")
    print("⚠️  Production için: export SECRET_KEY='your-secret-key-here'")
    
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24 * 7  # 7 gün

security = HTTPBearer()

def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Şifreyi doğrula - bcrypt direkt kullan"""
    try:
        # Bcrypt 72 byte limit - şifreyi encode et ve sınırla
        password_bytes = plain_password.encode('utf-8')
        if len(password_bytes) > 72:
            password_bytes = password_bytes[:72]
            plain_password = password_bytes.decode('utf-8', errors='ignore')
        
        # Bcrypt hash'i bytes'a çevir
        if isinstance(hashed_password, str):
            hashed_password_bytes = hashed_password.encode('utf-8')
        else:
            hashed_password_bytes = hashed_password
            
        return bcrypt.checkpw(plain_password.encode('utf-8'), hashed_password_bytes)
    except Exception:
        return False

def get_password_hash(password: str) -> str:
    """Şifreyi hash'le - bcrypt direkt kullan"""
    # Bcrypt 72 byte limit kontrolü
    password_bytes = password.encode('utf-8')
    if len(password_bytes) > 72:
        raise ValueError("Şifre çok uzun (maksimum 72 karakter)")
    
    # Bcrypt ile hash'le (12 rounds)
    salt = bcrypt.gensalt(rounds=12)
    hashed = bcrypt.hashpw(password_bytes, salt)
    return hashed.decode('utf-8')

def create_access_token(data: dict, expires_delta: Optional[timedelta] = None):
    to_encode = data.copy()
    if expires_delta:
        expire = utcnow() + expires_delta
    else:
        expire = utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return encoded_jwt

async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security)
) -> UserDB:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        token = credentials.credentials
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        user_id_str = payload.get("sub")
        if user_id_str is None:
            raise credentials_exception
        # JWT'den gelen string'i integer'a çevir
        try:
            user_id: int = int(user_id_str)
        except (ValueError, TypeError):
            raise credentials_exception
    except JWTError:
        raise credentials_exception
    
    with Session(engine) as s:
        user = s.get(UserDB, user_id)
        if user is None:
            raise credentials_exception
        return user

async def get_current_active_user(
    current_user: UserDB = Depends(get_current_user)
) -> UserDB:
    if not current_user.is_active:
        raise HTTPException(status_code=400, detail="Inactive user")
    return current_user

# ----------------- In-memory (demo) -----------------------------------------
READINGS: Deque[dict] = deque(maxlen=5000)
ALERTS:   Deque[dict] = deque(maxlen=1000)

# ----------------- Eşikler / Fan --------------------------------------------
THRESHOLDS = {
    "temp":     {"min": 16.0, "max": 26.0},
    "humidity": {"min": 45.0, "max": 80.0},
    "co2":      {"max": 1200.0},
}
LOW_CONFIDENCE_THRESHOLD = 0.5  # Düşük güven skorları için daha hassas uyarı

CLASS_INFO: Dict[str, Dict[str, Any]] = {
    # Money Plant
    "Money_Plant_Healthy": {
        "display": "Money Plant • Sağlıklı",
        "tips": [
            "Bitki sağlıklı görünüyor.",
            "Drenajı güçlü, hafif nemli toprakta tutmaya devam edin.",
            "Ayda bir yaprakları nemli bezle silerek tozdan arındırın.",
        ],
    },
    "Money_Plant_Bacterial_wilt_disease": {
        "display": "Money Plant • Bakteriyel Solgunluk",
        "tips": [
            "Hastalık ilerlememesi için etkilenen yaprakları budayın ve uzaklaştırın.",
            "Toprakta su birikmesini önleyin, drenajı artırın.",
            "Gerekiyorsa bakır bazlı fungisit kullanımı için uzman görüşü alın.",
        ],
    },
    "Money_Plant_Manganese_Toxicity": {
        "display": "Money Plant • Manganez Toksisitesi",
        "tips": [
            "Toprağı bol suyla yıkayarak fazla manganezin uzaklaşmasını sağlayın.",
            "Bir süre mangan içeren gübre kullanımını durdurun.",
            "Yeni sürgünleri izlemeye devam edin; belirtiler kalırsa toprak değiştirin.",
        ],
    },
    # Aloe
    "Aloe_Healthy": {
        "display": "Aloe Vera • Sağlıklı",
    },
    "Aloe_Anthracnose": {
        "display": "Aloe Vera • Antraknoz",
        "tips": [
            "Lekeli yaprakları dikkatlice budayın ve imha edin.",
            "Bitkiyi daha iyi hava sirkülasyonu olan bir ortama alın.",
            "Bakır bazlı fungisit uygulamasını değerlendirin.",
        ],
    },
    "Aloe_Sunburn": {
        "display": "Aloe Vera • Güneş Yanığı",
        "tips": [
            "Kısmi gölge sağlayarak doğrudan güneşten koruyun.",
            "Sıcaklık dalgalanmalarını azaltın, ani güneş ışığına maruz bırakmayın.",
        ],
    },
    "Aloe_LeafSpot": {
        "display": "Aloe Vera • Yaprak Lekesi",
    },
    "Aloe_Rust": {
        "display": "Aloe Vera • Pas",
    },
    # Snake Plant
    "Snake_Plant_Healthy": {
        "display": "Sansevieria • Sağlıklı",
    },
    "Snake_Plant_Leaf_Withering": {
        "display": "Sansevieria • Yaprak Solması",
        "tips": [
            "Fazla sulamadan kaçının; toprak kuruyana kadar bekleyin.",
            "Kökleri çürüme belirtileri için kontrol edin.",
        ],
    },
    # Spider Plant
    "Spider_Plant_Healthy": {
        "display": "Spider Plant • Sağlıklı",
    },
    "Spider_Plant_Leaf_Tip_Necrosis": {
        "display": "Spider Plant • Yaprak Ucu Nekrozu",
        "tips": [
            "Musluk suyu klor/flor içeriyorsa dinlendirilmiş su kullanın.",
            "Nem seviyesini artırmak için yaprakları düzenli olarak püskürtün.",
        ],
    },
}

FAN = {"mode": "auto", "state": "off", "last_change": None}
HEATER = {"mode": "auto", "state": "off", "last_change": None}
HUMIDIFIER = {"mode": "auto", "state": "off", "last_change": None}
ACTUATORS = {
    "fan": FAN,
    "heater": HEATER,
    "humidifier": HUMIDIFIER,
}

# Her actuator için 5 ardışık normal ölçüm sonrası otomatik kapatma
NORMAL_OK_TARGET = 5
NORMAL_OK_STREAK = {
    "fan": 0,
    "heater": 0,
    "humidifier": 0,
}


def _actuator_snapshot(device: str) -> Dict[str, Any]:
    data = ACTUATORS[device]
    return {
        "mode": data["mode"],
        "state": data["state"],
        "last_change": data["last_change"],
    }

# ----------------- ML MODELS -------------------------------------------------
BASE_DIR = Path(__file__).resolve().parent
MODELS_DIR = BASE_DIR / "models"
INDOOR_WEIGHTS = MODELS_DIR / "indoor_classifier.pt"
INDOOR_CLASSES = MODELS_DIR / "indoor_classes.json"
OUTDOOR_WEIGHTS = MODELS_DIR / "outdoor_classifier.pt"
OUTDOOR_CLASSES = MODELS_DIR / "outdoor_classes.json"
PLANTVILLAGE_WEIGHTS = MODELS_DIR / "plantvillage_multi.pt"

MODEL_REGISTRY: Dict[str, Any] = {
    # "indoor": PlantClassifier(INDOOR_WEIGHTS, INDOOR_CLASSES),  # Kaldırıldı
    "outdoor": PlantClassifier(OUTDOOR_WEIGHTS, OUTDOOR_CLASSES),
    "plantvillage": PlantVillageClassifier(PLANTVILLAGE_WEIGHTS),
}


def available_models(preferred: Optional[str] = None) -> List[str]:
    keys = []
    if preferred:
        clf = MODEL_REGISTRY.get(preferred)
        if clf and clf.is_ready():
            keys.append(preferred)
    for name, clf in MODEL_REGISTRY.items():
        if name == preferred:
            continue
        if clf.is_ready():
            keys.append(name)
    return keys


def recommendation_for_class(class_name: str) -> List[str]:
    info = CLASS_INFO.get(class_name)
    if info and info.get("tips"):
        return info["tips"]

    name = class_name.lower()
    if "healthy" in name:
        return [
            "Bitki sağlıklı görünüyor.",
            "Mevcut bakım rutininizi sürdürün.",
            "Düzenli olarak yaprakları kontrol etmeye devam edin.",
        ]
    hints = []
    if any(keyword in name for keyword in ["blight", "rot", "mold", "rust"]):
        hints.append("Mantar/bakteri kaynaklı olabilir; fungisit veya bakır bazlı ilaçları değerlendirin.")
    if "leaf" in name and "spot" in name:
        hints.append("Yaprak lekeleri için önce enfekte yaprakları temizleyin, hava sirkülasyonunu artırın.")
    if "mite" in name or "pest" in name:
        hints.append("Zararlıları mekanik olarak uzaklaştırın, gerekirse biyolojik/kimyasal mücadele uygulayın.")
    if "sun" in name:
        hints.append("Aşırı güneş/ısıdan kaçının, yarı gölgeli bir ortama alın.")
    if not hints:
        hints.append("Belirtileri yakından takip edin, gerekirse uzman desteği alın.")
    hints.append("Sulama, ışık ve besin dengesini gözden geçirin.")
    return hints

# ----------------- Schemas ---------------------------------------------------
class ReadingIn(BaseModel):
    sensor_id: str
    type: str
    value: float
    ts: Optional[datetime] = None

    @field_validator("type")
    @classmethod
    def check_type(cls, v: str):
        if v not in {"temp", "humidity", "co2"}:
            raise ValueError("type must be one of: temp, humidity, co2")
        return v

class UserRegister(BaseModel):
    email: EmailStr
    username: str
    password: str
    full_name: Optional[str] = None

    @field_validator("password")
    @classmethod
    def validate_password(cls, v: str):
        if len(v) < 6:
            raise ValueError("Şifre en az 6 karakter olmalıdır")
        if len(v.encode('utf-8')) > 72:
            raise ValueError("Şifre çok uzun (maksimum 72 karakter)")
        return v

    @field_validator("username")
    @classmethod
    def validate_username(cls, v: str):
        if len(v) < 3:
            raise ValueError("Kullanıcı adı en az 3 karakter olmalıdır")
        if len(v) > 50:
            raise ValueError("Kullanıcı adı çok uzun (maksimum 50 karakter)")
        return v

class UserLogin(BaseModel):
    username: str
    password: str

class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: dict

class UserResponse(BaseModel):
    id: int
    email: str
    username: str
    full_name: Optional[str] = None
    created_at: datetime

# ----------------- Endpoints -------------------------------------------------

@app.get("/api/v1/stats/series")
def stats_series(
    sensor: Literal["temp","humidity","co2"] = "temp",
    bucket: Literal["daily","hourly"] = "daily",
    days: int = 7,
    hours: int = 24,
):
    """
    daily: son 'days' gün, gün bazında gruplanmış min/max/avg/count
    hourly: son 'hours' saat, saat bazında gruplanmış min/max/avg/count
    Dönen: [{bucket: "...", count, min, max, avg}]
    """
    now_utc = utcnow()

    with Session(engine) as s:
        if bucket == "daily":
            cutoff = now_utc - timedelta(days=max(days, 1))
            # SQLite: DATE(ts) ile grup
            d_label = func.date(ReadingDB.ts).label("d")
            q = (
                s.query(
                    d_label,
                    func.count(ReadingDB.id).label("c"),
                    func.min(ReadingDB.value).label("mn"),
                    func.max(ReadingDB.value).label("mx"),
                    func.avg(ReadingDB.value).label("av"),
                )
                .filter(ReadingDB.type == sensor, ReadingDB.ts >= cutoff)
                .group_by(d_label)
                .order_by(d_label.asc())
            )
            rows = q.all()
            return [
                {"bucket": d, "count": c, "min": mn, "max": mx, "avg": av}
                for d, c, mn, mx, av in rows
            ]

        else:  # hourly
            cutoff = now_utc - timedelta(hours=max(hours, 1))
            # SQLite: strftime('%Y-%m-%d %H:00:00', ts) ile saat başına grup
            h_expr = func.strftime("%Y-%m-%d %H:00:00", ReadingDB.ts).label("h")
            q = (
                s.query(
                    h_expr,
                    func.count(ReadingDB.id).label("c"),
                    func.min(ReadingDB.value).label("mn"),
                    func.max(ReadingDB.value).label("mx"),
                    func.avg(ReadingDB.value).label("av"),
                )
                .filter(ReadingDB.type == sensor, ReadingDB.ts >= cutoff)
                .group_by(h_expr)
                .order_by(h_expr.asc())
            )
            rows = q.all()
            return [
                {"bucket": h, "count": c, "min": mn, "max": mx, "avg": av}
                for h, c, mn, mx, av in rows
            ]


@app.get("/api/v1/health")
def health():
    return {"status": "ok"}

# ----------------- AUTH ENDPOINTS -------------------------------------------
@app.post("/api/v1/auth/register", response_model=Token)
def register(user_data: UserRegister):
    """Kullanıcı kaydı"""
    with Session(engine) as s:
        # Email kontrolü
        existing_email = s.exec(select(UserDB).where(UserDB.email == user_data.email)).first()
        if existing_email:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Email already registered"
            )
        
        # Username kontrolü
        existing_username = s.exec(select(UserDB).where(UserDB.username == user_data.username)).first()
        if existing_username:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Username already taken"
            )
        
        # Şifre hash'leme (validation zaten yapıldı)
        try:
            hashed_password = get_password_hash(user_data.password)
        except ValueError as e:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=str(e)
            )
        new_user = UserDB(
            email=user_data.email,
            username=user_data.username,
            hashed_password=hashed_password,
            full_name=user_data.full_name,
            created_at=utcnow(),
            is_active=True
        )
        s.add(new_user)
        s.commit()
        s.refresh(new_user)
        
        # Token oluştur (JWT'de sub string olmalı)
        access_token = create_access_token(data={"sub": str(new_user.id)})
        
        return {
            "access_token": access_token,
            "token_type": "bearer",
            "user": {
                "id": new_user.id,
                "email": new_user.email,
                "username": new_user.username,
                "full_name": new_user.full_name,
                "created_at": iso_z(new_user.created_at),
            }
        }

@app.post("/api/v1/auth/login", response_model=Token)
def login(credentials: UserLogin):
    """Kullanıcı girişi"""
    with Session(engine) as s:
        # Username veya email ile giriş yapılabilir
        user = s.exec(
            select(UserDB).where(
                (UserDB.username == credentials.username) | 
                (UserDB.email == credentials.username)
            )
        ).first()
        
        if not user:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Incorrect username or password"
            )
        
        if not verify_password(credentials.password, user.hashed_password):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Incorrect username or password"
            )
        
        if not user.is_active:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Inactive user"
            )
        
        # Token oluştur (JWT'de sub string olmalı)
        access_token = create_access_token(data={"sub": str(user.id)})
        
        return {
            "access_token": access_token,
            "token_type": "bearer",
            "user": {
                "id": user.id,
                "email": user.email,
                "username": user.username,
                "full_name": user.full_name,
                "created_at": iso_z(user.created_at),
            }
        }

@app.get("/api/v1/auth/me", response_model=UserResponse)
def get_current_user_info(current_user: UserDB = Depends(get_current_active_user)):
    """Mevcut kullanıcı bilgilerini döner"""
    return UserResponse(
        id=current_user.id,
        email=current_user.email,
        username=current_user.username,
        full_name=current_user.full_name,
        created_at=current_user.created_at,
    )

@app.post("/api/v1/ingest")
def ingest(r: ReadingIn):
    """
    Sensör verisini alır, DB'ye yazar (UTC aware), eşikleri kontrol eder,
    gerekli uyarıyı üretir ve fan otomasyonunu yönetir.
    """
    try:
        ts_utc = to_utc(r.ts)

        # In-memory log (Z'li string)
        READINGS.append({
            "sensor_id": r.sensor_id,
            "type": r.type,
            "value": float(r.value),
            "ts": iso_z(ts_utc),
        })

        # DB: reading insert (aware datetime) - retry logic ile
        db_success = False
        for attempt in range(3):  # 3 deneme
            try:
                with Session(engine) as s:
                    s.add(ReadingDB(
                        sensor_id=r.sensor_id,
                        type=r.type,
                        value=float(r.value),
                        ts=ts_utc,
                    ))
                    s.commit()
                db_success = True
                break
            except Exception as db_err:
                if attempt < 2:  # Son deneme değilse bekle
                    import time
                    time.sleep(0.1 * (attempt + 1))  # Kademeli bekleme
                else:
                    # Son deneme de başarısız - sessizce devam et
                    pass

        # Eşik kontrolü
        th = THRESHOLDS.get(r.type, {})
        if r.type in ("temp", "humidity"):
            if "min" not in th or "max" not in th:
                out = False
            else:
                out = not (th["min"] <= r.value <= th["max"])
        elif r.type == "co2":
            if "max" not in th:
                out = False
            else:
                out = r.value > th["max"]
        else:
            out = False

        if out:
            # --- WARN ALERT ---
            msg = f"{r.type} out of range: {r.value}"
            ALERTS.append({
                "level": "warn",
                "source": "threshold",
                "message": msg,
                "ts": iso_z(utcnow()),
            })
            try:
                with Session(engine) as s:
                    s.add(AlertDB(level="warn", source="threshold", message=msg, ts=utcnow()))
                    s.commit()
            except Exception as db_err:
                print(f"Alert DB insert error: {db_err}")

            # Normal okuma sayaçlarını sıfırla
            for key in NORMAL_OK_STREAK:
                NORMAL_OK_STREAK[key] = 0

            # --- FAN AUTO → ON (CO2 eşiği aşıldıysa) ---
            if r.type == "co2" and FAN["mode"] == "auto" and FAN["state"] == "off":
                FAN["state"] = "on"
                FAN["last_change"] = iso_z(utcnow())
                try:
                    with Session(engine) as s:
                        s.add(ActuatorEventDB(
                            device="fan",
                            action="on",
                            reason="automation",
                            mode=FAN["mode"],
                            state=FAN["state"],
                            ts=utcnow(),
                        ))
                        s.commit()
                except Exception as db_err:
                    print(f"ActuatorEvent DB insert error: {db_err}")

            # --- HEATER AUTO → ON (Sıcaklık eşiği altındaysa) ---
            if r.type == "temp" and HEATER["mode"] == "auto" and HEATER["state"] == "off":
                temp_th = THRESHOLDS.get("temp", {})
                if "min" in temp_th and r.value < temp_th["min"]:
                    HEATER["state"] = "on"
                    HEATER["last_change"] = iso_z(utcnow())
                    try:
                        with Session(engine) as s:
                            s.add(ActuatorEventDB(
                                device="heater",
                                action="on",
                                reason="automation",
                                mode=HEATER["mode"],
                                state=HEATER["state"],
                                ts=utcnow(),
                            ))
                            s.commit()
                    except Exception as db_err:
                        print(f"ActuatorEvent DB insert error: {db_err}")

            # --- HUMIDIFIER AUTO → ON (Nem eşiği altındaysa) ---
            if r.type == "humidity" and HUMIDIFIER["mode"] == "auto" and HUMIDIFIER["state"] == "off":
                hum_th = THRESHOLDS.get("humidity", {})
                if "min" in hum_th and r.value < hum_th["min"]:
                    HUMIDIFIER["state"] = "on"
                    HUMIDIFIER["last_change"] = iso_z(utcnow())
                    try:
                        with Session(engine) as s:
                            s.add(ActuatorEventDB(
                                device="humidifier",
                                action="on",
                                reason="automation",
                                mode=HUMIDIFIER["mode"],
                                state=HUMIDIFIER["state"],
                                ts=utcnow(),
                            ))
                            s.commit()
                    except Exception as db_err:
                        print(f"ActuatorEvent DB insert error: {db_err}")

        else:
            # --- NORMAL OKUMA ---
            if r.type == "co2":
                NORMAL_OK_STREAK["fan"] += 1
                if FAN["mode"] == "auto" and FAN["state"] == "on" and NORMAL_OK_STREAK["fan"] >= NORMAL_OK_TARGET:
                    FAN["state"] = "off"
                    FAN["last_change"] = iso_z(utcnow())
                    info_msg = f"fan auto-off after {NORMAL_OK_STREAK['fan']} normal readings"
                    ALERTS.append({
                        "level": "info",
                        "source": "automation",
                        "message": info_msg,
                        "ts": iso_z(utcnow()),
                    })
                    try:
                        with Session(engine) as s:
                            s.add(AlertDB(level="info", source="automation", message=info_msg, ts=utcnow()))
                            s.commit()
                    except Exception as db_err:
                        print(f"Alert DB insert error: {db_err}")
                    try:
                        with Session(engine) as s:
                            s.add(ActuatorEventDB(
                                device="fan",
                                action="off",
                                reason="automation",
                                mode=FAN["mode"],
                                state=FAN["state"],
                                ts=utcnow(),
                            ))
                            s.commit()
                    except Exception as db_err:
                        print(f"ActuatorEvent DB insert error: {db_err}")
                    NORMAL_OK_STREAK["fan"] = 0

            elif r.type == "temp":
                NORMAL_OK_STREAK["heater"] += 1
                if HEATER["mode"] == "auto" and HEATER["state"] == "on" and NORMAL_OK_STREAK["heater"] >= NORMAL_OK_TARGET:
                    HEATER["state"] = "off"
                    HEATER["last_change"] = iso_z(utcnow())
                    info_msg = f"heater auto-off after {NORMAL_OK_STREAK['heater']} normal readings"
                    ALERTS.append({
                        "level": "info",
                        "source": "automation",
                        "message": info_msg,
                        "ts": iso_z(utcnow()),
                    })
                    try:
                        with Session(engine) as s:
                            s.add(AlertDB(level="info", source="automation", message=info_msg, ts=utcnow()))
                            s.commit()
                    except Exception as db_err:
                        print(f"Alert DB insert error: {db_err}")
                    try:
                        with Session(engine) as s:
                            s.add(ActuatorEventDB(
                                device="heater",
                                action="off",
                                reason="automation",
                                mode=HEATER["mode"],
                                state=HEATER["state"],
                                ts=utcnow(),
                            ))
                            s.commit()
                    except Exception as db_err:
                        print(f"ActuatorEvent DB insert error: {db_err}")
                    NORMAL_OK_STREAK["heater"] = 0

            elif r.type == "humidity":
                NORMAL_OK_STREAK["humidifier"] += 1
                if HUMIDIFIER["mode"] == "auto" and HUMIDIFIER["state"] == "on" and NORMAL_OK_STREAK["humidifier"] >= NORMAL_OK_TARGET:
                    HUMIDIFIER["state"] = "off"
                    HUMIDIFIER["last_change"] = iso_z(utcnow())
                    info_msg = f"humidifier auto-off after {NORMAL_OK_STREAK['humidifier']} normal readings"
                    ALERTS.append({
                        "level": "info",
                        "source": "automation",
                        "message": info_msg,
                        "ts": iso_z(utcnow()),
                    })
                    try:
                        with Session(engine) as s:
                            s.add(AlertDB(level="info", source="automation", message=info_msg, ts=utcnow()))
                            s.commit()
                    except Exception as db_err:
                        print(f"Alert DB insert error: {db_err}")
                    try:
                        with Session(engine) as s:
                            s.add(ActuatorEventDB(
                                device="humidifier",
                                action="off",
                                reason="automation",
                                mode=HUMIDIFIER["mode"],
                                state=HUMIDIFIER["state"],
                                ts=utcnow(),
                            ))
                            s.commit()
                    except Exception as db_err:
                        print(f"ActuatorEvent DB insert error: {db_err}")
                    NORMAL_OK_STREAK["humidifier"] = 0

        return {"ok": True}
    
    except Exception as e:
        import traceback
        error_msg = f"Ingest error: {str(e)}\n{traceback.format_exc()}"
        print(error_msg)
        # Hata olsa bile 200 dön (simulate.py için)
        return {"ok": False, "error": str(e)}

@app.get("/api/v1/weather")
async def get_weather(city: str = "Istanbul", country_code: str = "TR", lat: Optional[float] = None, lon: Optional[float] = None):
    """
    Hava durumu bilgilerini döner (Open-Meteo API kullanır - ücretsiz, API key gerektirmez)
    city: Şehir adı (default: Istanbul) - koordinat yoksa kullanılır
    country_code: Ülke kodu (default: TR)
    lat: Enlem (opsiyonel, varsa direkt kullanılır)
    lon: Boylam (opsiyonel, varsa direkt kullanılır)
    """
    # Eğer koordinat verilmişse direkt kullan
    if lat is not None and lon is not None:
        coords = {"lat": lat, "lon": lon}
        city_name = city  # Şehir adını parametre olarak kullan
    else:
        # Şehir adından koordinat bulmak için Open-Meteo Geocoding API kullan
        try:
            geocoding_url = "https://geocoding-api.open-meteo.com/v1/search"
            geocoding_params = {
                "name": city,
                "count": 1,
                "language": "tr",
                "format": "json",
            }
            async with httpx.AsyncClient(timeout=10.0) as client:
                geo_response = await client.get(geocoding_url, params=geocoding_params)
                geo_response.raise_for_status()
                geo_data = geo_response.json()
            
            if geo_data.get("results") and len(geo_data["results"]) > 0:
                result = geo_data["results"][0]
                coords = {"lat": result["latitude"], "lon": result["longitude"]}
                city_name = result.get("name", city)  # API'den gelen şehir adı
            else:
                # Geocoding başarısız, default Istanbul kullan
                coords = {"lat": 41.0082, "lon": 28.9784}
                city_name = "Istanbul"
        except Exception as e:
            print(f"Geocoding error: {e}")
            # Hata durumunda default Istanbul kullan
            coords = {"lat": 41.0082, "lon": 28.9784}
            city_name = "Istanbul"
    
    try:
        # Open-Meteo API - tamamen ücretsiz, API key gerektirmez
        url = "https://api.open-meteo.com/v1/forecast"
        params = {
            "latitude": coords["lat"],
            "longitude": coords["lon"],
            "current": "temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m,apparent_temperature",
            "daily": "weather_code,temperature_2m_max,temperature_2m_min",
            "timezone": "Europe/Istanbul",
            "forecast_days": 7,  # 7 günlük tahmin
        }
        
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.get(url, params=params)
            response.raise_for_status()
            data = response.json()
        
        current = data["current"]
        temp = current["temperature_2m"]
        feels_like = current["apparent_temperature"]
        humidity = current["relative_humidity_2m"]
        wind_speed = current["wind_speed_10m"]
        weather_code = int(current["weather_code"])
        
        # WMO Weather interpretation codes (WW) -> Türkçe açıklama
        weather_codes = {
            0: "Açık",
            1: "Çoğunlukla açık",
            2: "Kısmen bulutlu",
            3: "Kapalı",
            45: "Sisli",
            48: "Donan sisli",
            51: "Hafif çiseleyen yağmur",
            53: "Orta çiseleyen yağmur",
            55: "Yoğun çiseleyen yağmur",
            56: "Hafif donan çiseleme",
            57: "Yoğun donan çiseleme",
            61: "Hafif yağmur",
            63: "Orta yağmur",
            65: "Yoğun yağmur",
            66: "Hafif donan yağmur",
            67: "Yoğun donan yağmur",
            71: "Hafif kar",
            73: "Orta kar",
            75: "Yoğun kar",
            77: "Kar taneleri",
            80: "Hafif sağanak",
            81: "Orta sağanak",
            82: "Yoğun sağanak",
            85: "Hafif kar sağanağı",
            86: "Yoğun kar sağanağı",
            95: "Fırtına",
            96: "Dolu ile fırtına",
            99: "Şiddetli dolu ile fırtına",
        }
        
        description = weather_codes.get(weather_code, "Bilinmiyor")
        
        # Icon seçimi (basit mapping)
        if weather_code in [0, 1]:
            icon = "clear"
        elif weather_code in [2, 3]:
            icon = "clouds"
        elif weather_code in [45, 48]:
            icon = "mist"
        elif weather_code in range(51, 68):
            icon = "rain"
        elif weather_code in range(71, 78):
            icon = "snow"
        elif weather_code in range(80, 83):
            icon = "rain"
        elif weather_code in range(95, 100):
            icon = "thunderstorm"
        else:
            icon = "clouds"
        
        # Haftalık tahmin verilerini al
        daily_forecast = []
        if "daily" in data:
            daily = data["daily"]
            daily_codes = daily.get("weather_code", [])
            daily_max = daily.get("temperature_2m_max", [])
            daily_min = daily.get("temperature_2m_min", [])
            daily_time = daily.get("time", [])
            
            for i in range(min(7, len(daily_codes))):
                day_code = int(daily_codes[i])
                day_description = weather_codes.get(day_code, "Bilinmiyor")
                
                # Icon seçimi
                if day_code in [0, 1]:
                    day_icon = "clear"
                elif day_code in [2, 3]:
                    day_icon = "clouds"
                elif day_code in [45, 48]:
                    day_icon = "mist"
                elif day_code in range(51, 68):
                    day_icon = "rain"
                elif day_code in range(71, 78):
                    day_icon = "snow"
                elif day_code in range(80, 83):
                    day_icon = "rain"
                elif day_code in range(95, 100):
                    day_icon = "thunderstorm"
                else:
                    day_icon = "clouds"
                
                daily_forecast.append({
                    "date": daily_time[i] if i < len(daily_time) else "",
                    "max_temp": round(daily_max[i], 1) if i < len(daily_max) else 0.0,
                    "min_temp": round(daily_min[i], 1) if i < len(daily_min) else 0.0,
                    "weather_code": day_code,
                    "description": day_description,
                    "icon": day_icon,
                })
        
        return {
            "temp": round(temp, 1),
            "feels_like": round(feels_like, 1),
            "humidity": int(humidity),
            "wind_speed": round(wind_speed * 3.6, 1),  # m/s'den km/h'ye çevir
            "description": description,
            "icon": icon,
            "weather_code": weather_code,  # Frontend'de ikon seçimi için
            "city": city_name,
            "country": country_code,
            "forecast": daily_forecast,  # 7 günlük tahmin
        }
    except Exception as e:
        print(f"Weather API error: {e}")
        # Hata durumunda mock data dön
        return {
            "temp": 23.0,
            "feels_like": 24.0,
            "humidity": 52,
            "wind_speed": 8.0,
            "description": "Parçalı bulutlu",
            "icon": "clouds",
            "weather_code": 2,
            "city": city,
            "country": country_code,
            "forecast": [],  # Mock data'da tahmin yok
        }

@app.get("/api/v1/latest")
def latest():
    """Her sensör tipi için en son okumayı döner."""
    with Session(engine) as s:
        temp = s.exec(
            select(ReadingDB)
            .where(ReadingDB.type == "temp")
            .order_by(ReadingDB.ts.desc())
            .limit(1)
        ).first()
        humidity = s.exec(
            select(ReadingDB)
            .where(ReadingDB.type == "humidity")
            .order_by(ReadingDB.ts.desc())
            .limit(1)
        ).first()
        co2 = s.exec(
            select(ReadingDB)
            .where(ReadingDB.type == "co2")
            .order_by(ReadingDB.ts.desc())
            .limit(1)
        ).first()
        
        return {
            "temp": temp.value if temp else 0.0,
            "humidity": humidity.value if humidity else 0.0,
            "co2": co2.value if co2 else 0.0,
        }

@app.get("/api/v1/readings")
def readings(sensor_id: Optional[str] = None, limit: int = 100):
    """DB'den okur, ts'leri Z'li ISO string olarak döner."""
    with Session(engine) as s:
        if sensor_id:
            stmt = (
                select(ReadingDB)
                .where(ReadingDB.sensor_id == sensor_id)
                .order_by(ReadingDB.ts.desc())
                .limit(limit)
            )
        else:
            stmt = select(ReadingDB).order_by(ReadingDB.ts.desc()).limit(limit)
        rows = s.exec(stmt).all()
        out = []
        for r in rows:
            # Eski (naive) kayıtlar varsa UTC varsay
            ts = to_utc(r.ts)
            out.append({
                "id": r.id,
                "sensor_id": r.sensor_id,
                "type": r.type,
                "value": r.value,
                "ts": iso_z(ts),
            })
        return out

@app.get("/api/v1/fan/history")
def fan_history(limit: int = 100):
    """Backward compatibility için fan history endpoint'i"""
    return actuator_history(device="fan", limit=limit)

@app.get("/api/v1/actuator/history")
def actuator_history(device: Optional[str] = None, limit: int = 100):
    """Tüm actuator'lar veya belirli bir actuator için event history"""
    with Session(engine) as s:
        query = select(ActuatorEventDB).order_by(ActuatorEventDB.ts.desc())
        if device:
            query = query.where(ActuatorEventDB.device == device)
        query = query.limit(limit)
        rows = s.exec(query).all()
        out = []
        for e in rows:
            out.append({
                "id": e.id,
                "device": e.device,
                "action": e.action,
                "reason": e.reason,
                "mode": e.mode,
                "state": e.state,
                "ts": iso_z(to_utc(e.ts)),
            })
        return out


@app.get("/api/v1/alerts")
def alerts(limit: int = 100):
    with Session(engine) as s:
        rows = s.exec(select(AlertDB).order_by(AlertDB.ts.desc()).limit(limit)).all()
        out = []
        for a in rows:
            ts = to_utc(a.ts)
            out.append({
                "id": a.id,
                "level": a.level,
                "source": a.source,
                "message": a.message,
                "ts": iso_z(ts),
            })
        return out

class ControlPayload(BaseModel):
    action: Literal["on", "off", "auto"]


def _set_actuator(device: str, action: str):
    actuator = ACTUATORS[device]
    actuator["last_change"] = iso_z(utcnow())
    if action in {"on", "off"}:
        actuator["mode"] = "manual"
        actuator["state"] = action
    else:
        actuator["mode"] = "auto"
        # Otomatik moda geçerken cihazı kapalı varsay
        actuator["state"] = "off"

    # Tüm actuator'lar için event kaydı
    try:
        with Session(engine) as s:
            s.add(ActuatorEventDB(
                device=device,
                action=action,
                reason="manual",
                mode=actuator["mode"],
                state=actuator["state"],
                ts=utcnow(),
            ))
            s.commit()
    except Exception as db_err:
        print(f"ActuatorEvent DB insert error: {db_err}")

    return {"ok": True, "device": device, "state": actuator}


@app.get("/api/v1/actuators")
def actuator_list():
    return {device: _actuator_snapshot(device) for device in ACTUATORS}


@app.get("/api/v1/actuator/{device}")
def actuator_status(device: Literal["fan", "heater", "humidifier"]):
    return _actuator_snapshot(device)


@app.post("/api/v1/control/{device}")
def actuator_control(device: Literal["fan", "heater", "humidifier"], payload: ControlPayload):
    return _set_actuator(device, payload.action)


@app.post("/api/v1/control/fan")
def fan_control(action: str):
    if action not in {"on", "off", "auto"}:
        return {"ok": False, "error": "invalid action"}
    return _set_actuator("fan", action)


# ----------------- MODEL METRİKLERİ ENDPOINT -----------------
@app.get("/api/v1/model-metrics")
async def get_model_metrics(
    current_user: UserDB = Depends(get_current_active_user),
):
    """
    Model metriklerini döndürür: Confusion Matrix, Accuracy, Precision, Recall, F1-Score
    Test seti üzerinde değerlendirme yapar.
    """
    try:
        import torch
        import numpy as np
        from sklearn.metrics import confusion_matrix, classification_report
        from torch.utils.data import Dataset, DataLoader
        import pandas as pd
        import os
        from sklearn.model_selection import train_test_split
        import albumentations as A
        from albumentations.pytorch import ToTensorV2
        
        # Dataset sınıfı (notebook'tan)
        class PlantMultiOutputDataset(Dataset):
            def __init__(self, dataframe, transform=None):
                self.df = dataframe
                self.transform = transform
                self.plant_names = sorted(set(label.split("___")[0] for label in dataframe['labels']))
                self.status_names = sorted(set(label.split("___")[1] for label in dataframe['labels']))
                self.plant_map = {name: idx for idx, name in enumerate(self.plant_names)}
                self.status_map = {name.lower(): idx for idx, name in enumerate(self.status_names)}

            def __len__(self):
                return len(self.df)

            def __getitem__(self, idx):
                row = self.df.iloc[idx]
                img = Image.open(row.filepaths).convert("RGB")
                plant_str, status_str = row.labels.split("___")
                plant_label = self.plant_map[plant_str]
                status_label = self.status_map[status_str.lower()]
                
                if self.transform:
                    img = self.transform(image=np.array(img))['image']
                
                return img, torch.tensor(plant_label), torch.tensor(status_label)

        def define_paths(data_dir):
            filepaths = []
            labels = []
            for fold in os.listdir(data_dir):
                foldpath = os.path.join(data_dir, fold)
                if os.path.isdir(foldpath):
                    for file in os.listdir(foldpath):
                        if file.lower().endswith(('.png', '.jpg', '.jpeg')):
                            filepaths.append(os.path.join(foldpath, file))
                            labels.append(fold)
            return pd.DataFrame({'filepaths': filepaths, 'labels': labels})

        def split_df(df):
            train_df, dummy_df = train_test_split(df, train_size=0.8, stratify=df['labels'], random_state=42)
            val_df, test_df = train_test_split(dummy_df, train_size=0.5, stratify=dummy_df['labels'], random_state=42)
            return train_df.reset_index(drop=True), val_df.reset_index(drop=True), test_df.reset_index(drop=True)

        # Model yükle
        from .plantvillage_classifier import PlantVillageClassifier, MultiOutputModel
        
        model_path = PLANTVILLAGE_WEIGHTS
        if not model_path.exists():
            raise HTTPException(
                status_code=404,
                detail={"error": "MODEL_NOT_FOUND", "message": "PlantVillage modeli bulunamadı."}
            )

        bundle = torch.load(model_path, map_location="cpu")
        plant_names = bundle.get("plant_names", [])
        status_names = bundle.get("status_names", [])

        device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        model = MultiOutputModel(len(plant_names), len(status_names))
        model.load_state_dict(bundle["state_dict"])
        model.eval()
        model.to(device)

        # Test seti yükle
        data_dir = Path("PlantVillage-Dataset/raw/color")
        if not data_dir.exists():
            raise HTTPException(
                status_code=404,
                detail={"error": "DATASET_NOT_FOUND", "message": "Dataset bulunamadı."}
            )

        df = define_paths(str(data_dir))
        train_df, val_df, test_df = split_df(df)

        test_transform = A.Compose([
            A.Resize(224, 224),
            A.Normalize(mean=(0.485, 0.456, 0.406), std=(0.229, 0.224, 0.225)),
            ToTensorV2()
        ])

        test_dataset = PlantMultiOutputDataset(test_df, transform=test_transform)
        test_loader = DataLoader(test_dataset, batch_size=32, shuffle=False, num_workers=0)

        # Tahmin yap
        all_plant_preds = []
        all_plant_labels = []
        all_health_preds = []
        all_health_labels = []

        with torch.no_grad():
            for x, y_plant, y_health in test_loader:
                x = x.to(device)
                plant_logits, health_logits = model(x)
                
                plant_preds = plant_logits.argmax(1).cpu().numpy()
                health_preds = health_logits.argmax(1).cpu().numpy()
                
                all_plant_preds.extend(plant_preds)
                all_plant_labels.extend(y_plant.numpy())
                all_health_preds.extend(health_preds)
                all_health_labels.extend(y_health.numpy())

        # Metrikler
        plant_acc = float(np.mean(np.array(all_plant_preds) == np.array(all_plant_labels)))
        health_acc = float(np.mean(np.array(all_health_preds) == np.array(all_health_labels)))

        # Confusion Matrix
        plant_cm = confusion_matrix(all_plant_labels, all_plant_preds).tolist()
        health_cm = confusion_matrix(all_health_labels, all_health_preds).tolist()

        # Classification Report
        plant_report = classification_report(
            all_plant_labels, all_plant_preds,
            target_names=plant_names,
            output_dict=True
        )
        health_report = classification_report(
            all_health_labels, all_health_preds,
            target_names=status_names,
            output_dict=True
        )

        return {
            "test_set_size": len(test_df),
            "accuracy": {
                "plant": plant_acc,
                "health": health_acc,
                "average": (plant_acc + health_acc) / 2
            },
            "confusion_matrices": {
                "plant": {
                    "matrix": plant_cm,
                    "class_names": plant_names,
                    "shape": [len(plant_names), len(plant_names)]
                },
                "health": {
                    "matrix": health_cm,
                    "class_names": status_names,
                    "shape": [len(status_names), len(status_names)]
                }
            },
            "classification_report": {
                "plant": {
                    "precision": plant_report["weighted avg"]["precision"],
                    "recall": plant_report["weighted avg"]["recall"],
                    "f1_score": plant_report["weighted avg"]["f1-score"]
                },
                "health": {
                    "precision": health_report["weighted avg"]["precision"],
                    "recall": health_report["weighted avg"]["recall"],
                    "f1_score": health_report["weighted avg"]["f1-score"]
                }
            }
        }

    except Exception as e:
        import traceback
        error_msg = f"Model metrikleri hesaplanırken hata: {str(e)}\n{traceback.format_exc()}"
        print(error_msg)
        raise HTTPException(
            status_code=500,
            detail={"error": "METRICS_ERROR", "message": str(e)}
        )


# ----------------- BİTKİ ANALİZİ ENDPOINT -----------------
@app.post("/api/v1/analyze-plant")
async def analyze_plant(
    image: UploadFile = File(...),
    model: Literal["auto", "outdoor", "plantvillage"] = "auto",
    current_user: UserDB = Depends(get_current_active_user),
):
    """
    Bitki fotoğrafını analiz eder. Indoor/outdoor sınıflandırıcılarını kullanır.
    """
    try:
        contents = await image.read()
        img = Image.open(io.BytesIO(contents))
        if img.mode != "RGB":
            img = img.convert("RGB")
        width, height = img.size

        model_keys = available_models(None if model == "auto" else model)
        model_results = []
        for key in model_keys:
            clf = MODEL_REGISTRY[key]
            try:
                pred = clf.predict(img)
                pred["model"] = key
                model_results.append(pred)
            except Exception as clf_err:
                print(f"Model inference error ({key}): {clf_err}")

        if not model_results:
            raise HTTPException(
                status_code=503,
                detail={
                    "error": "MODEL_UNAVAILABLE",
                    "message": "Eğitilmiş bitki modeli bulunamadı. Lütfen backend/models klasörüne .pt dosyası ekleyin.",
                },
            )

        # PlantVillage modeli için özel işleme
        is_plantvillage = False
        plantvillage_result = None
        for result in model_results:
            if result["model"] == "plantvillage" and "plant" in result and "health" in result:
                is_plantvillage = True
                plantvillage_result = result
                break

        # En yüksek güven skoruna sahip tahmini seç
        best = max(model_results, key=lambda r: float(r["confidence"]))
        best_class_name = best["class_name"]
        primary_confidence = float(best["confidence"])

        is_low_confidence = primary_confidence < LOW_CONFIDENCE_THRESHOLD
        status = "Model Tahmini" if not is_low_confidence else "Düşük Güven - Dikkatli Olun"
        message = None
        if is_low_confidence:
            message = (
                f"⚠️ Model bu fotoğrafta emin olamadı (Güven: %{int(primary_confidence * 100)}). "
                "Tahmin yanlış olabilir.\n\n"
                "📸 Daha iyi sonuç için:\n"
                "• Sadece yaprakları gösteren yakın çekim fotoğraf kullanın\n"
                "• Temiz, düz arka plan tercih edin\n"
                "• Yapraklar net ve odakta olsun\n"
                "• Doğal ışıkta çekin\n\n"
                "ℹ️ Not: Model PlantVillage dataset'inde eğitildi. "
                "Bu dataset kontrollü koşullarda çekilmiş yaprak fotoğrafları içerir. "
                "Tam bitki fotoğrafları veya karmaşık arka planlı görüntülerde performans düşebilir."
            )
            # Düşük güven skorunda alternatif modelleri öner
            if len(model_results) > 1:
                alt_models = [r for r in model_results if r["model"] != best["model"]]
                if alt_models:
                    alt_best = max(alt_models, key=lambda r: float(r["confidence"]))
                    alt_conf = float(alt_best["confidence"])
                    if alt_conf > primary_confidence * 0.7:  # Daha düşük eşik
                        alt_display = alt_best.get("class_name", "").replace("_", " ").replace("___", " • ")
                        message += f"\n\nAlternatif tahmin ({alt_best['model']}): {alt_display} (Güven: %{int(alt_conf * 100)})"

        # PlantVillage için özel işleme
        if is_plantvillage and plantvillage_result:
            plant_info = plantvillage_result["plant"]
            health_info = plantvillage_result["health"]
            combined_class = plantvillage_result["class_name"]  # "Plant___Status" formatı
            
            # Sağlık durumunu kontrol et
            is_healthy = "healthy" in health_info["class_name"].lower()
            health_score = health_info["confidence"] if is_healthy else 1 - health_info["confidence"]
            health_score = max(0.0, min(1.0, health_score))
            health_label = "Sağlıklı" if health_score >= 0.6 else "Riskli"
            
            # Display name oluştur
            plant_display = plant_info["class_name"].replace("_", " ")
            health_display = health_info["class_name"].replace("_", " ")
            primary_display = f"{plant_display} • {health_display}"
            
            # Öneriler - sağlık durumuna göre
            if is_healthy:
                recommendations = [
                    "Bitki sağlıklı görünüyor.",
                    "Mevcut bakım rutininizi sürdürün.",
                    "Düzenli olarak yaprakları kontrol etmeye devam edin.",
                ]
            else:
                recommendations = recommendation_for_class(health_info["class_name"])
                # Bitki türüne özel ek öneriler eklenebilir
            
            # Düşük güven skorunda ek uyarı
            if is_low_confidence:
                recommendations.insert(0, 
                    f"⚠️ Dikkat: Bu tahmin düşük güven skoruna sahip (%{int(primary_confidence * 100)}). "
                    "Model PlantVillage dataset'inde eğitildi ve sadece yaprak odaklı, temiz arka planlı fotoğraflarda iyi çalışır. "
                    "Tam bitki fotoğrafları veya karmaşık arka planlı görüntülerde yanlış tahmin yapabilir."
                )
            
            # Alternatif tahminler
            alternatives = [
                {
                    "model": r["model"],
                    "class_name": r.get("class_name", ""),
                    "display_name": CLASS_INFO.get(r.get("class_name", ""), {}).get(
                        "display", r.get("class_name", "").replace("_", " ").replace("___", " • ")
                    ),
                    "confidence": float(r.get("confidence", 0.0)),
                }
                for r in model_results[:5]
            ]
            
            return {
                "status": status,
                "message": message,
                "disease": combined_class,
                "disease_display": primary_display,
                "health_score": health_score,
                "health_label": health_label,
                "confidence_score": primary_confidence,
                "analysis": {
                    "model": "plantvillage",
                    "confidence": primary_confidence,
                    "plant": {
                        "name": plant_info["class_name"],
                        "confidence": plant_info["confidence"],
                    },
                    "health": {
                        "status": health_info["class_name"],
                        "confidence": health_info["confidence"],
                    },
                    "alternatives": alternatives,
                },
                "recommendations": recommendations,
                "image_size": {"width": width, "height": height},
            }

        # Diğer modeller için (indoor/outdoor)
        # Sağlık skoru ve etiketi
        class_name_lower = best_class_name.lower()
        is_healthy_class = "healthy" in class_name_lower
        health_score = primary_confidence if is_healthy_class else 1 - primary_confidence
        health_score = max(0.0, min(1.0, health_score))
        health_label = "Sağlıklı" if health_score >= 0.6 else "Riskli"

        # Alternatif tahminler
        alternatives = [
            {
                "model": r["model"],
                "class_name": r["class_name"],
                "display_name": CLASS_INFO.get(r["class_name"], {}).get(
                    "display", r["class_name"].replace("_", " ")
                ),
                "confidence": float(r["confidence"]),
            }
            for r in model_results[:5]
        ]

        primary_display = CLASS_INFO.get(best_class_name, {}).get(
            "display", best_class_name.replace("_", " ")
        )
        recommendations = recommendation_for_class(best_class_name)

        return {
            "status": status,
            "message": message,
            "disease": best_class_name,
            "disease_display": primary_display,
            "health_score": health_score,
            "health_label": health_label,
            "confidence_score": primary_confidence,
            "analysis": {
                "model": best["model"],
                "confidence": primary_confidence,
                "alternatives": alternatives,
            },
            "recommendations": recommendations,
            "image_size": {"width": width, "height": height},
        }

    except HTTPException:
        raise
    except Exception as e:
        return {
            "status": "Hata",
            "error": str(e),
            "health_score": 0.0,
            "confidence_score": 0.0,
        }
