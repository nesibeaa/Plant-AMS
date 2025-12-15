# backend/main.py
from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.responses import Response
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, field_validator
from typing import Optional, Deque, Dict, List, Literal, Any
from pathlib import Path
from collections import deque
from datetime import datetime, timezone
from datetime import timedelta
from sqlalchemy import text as sqltext
from sqlalchemy import func, event
import io
from PIL import Image
import numpy as np

from .plant_classifier import PlantClassifier


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

@app.on_event("startup")
def on_startup():
    SQLModel.metadata.create_all(engine)

# ----------------- In-memory (demo) -----------------------------------------
READINGS: Deque[dict] = deque(maxlen=5000)
ALERTS:   Deque[dict] = deque(maxlen=1000)

# ----------------- Eşikler / Fan --------------------------------------------
THRESHOLDS = {
    "temp":     {"min": 16.0, "max": 26.0},
    "humidity": {"min": 45.0, "max": 80.0},
    "co2":      {"max": 1200.0},
}
LOW_CONFIDENCE_THRESHOLD = 0.6

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

MODEL_REGISTRY: Dict[str, PlantClassifier] = {
    "indoor": PlantClassifier(INDOOR_WEIGHTS, INDOOR_CLASSES),
    "outdoor": PlantClassifier(OUTDOOR_WEIGHTS, OUTDOOR_CLASSES),
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


# ----------------- BİTKİ ANALİZİ ENDPOINT -----------------
@app.post("/api/v1/analyze-plant")
async def analyze_plant(
    image: UploadFile = File(...),
    model: Literal["auto", "indoor", "outdoor"] = "auto",
):
    """
    Bitki fotoğrafını analiz eder. En az bir eğitilmiş sınıflandırıcı gerektirir.
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

        sorted_results = sorted(model_results, key=lambda x: x["confidence"], reverse=True)
        best = sorted_results[0]

        primary_confidence = float(best["confidence"])
        is_low_confidence = primary_confidence < LOW_CONFIDENCE_THRESHOLD

        status = "Model Tahmini" if not is_low_confidence else "Düşük Güven"
        message = None
        if is_low_confidence:
            message = (
                "Model bu fotoğrafta emin olamadı. Daha net bir görüntü seçebilir ya da farklı açıdan tekrar deneyebilirsiniz."
            )

        class_name_lower = best["class_name"].lower()
        is_healthy_class = "healthy" in class_name_lower
        health_score = primary_confidence if is_healthy_class else 1 - primary_confidence
        health_score = max(0.0, min(1.0, health_score))
        health_label = "Sağlıklı" if health_score >= 0.6 else "Riskli"

        alternatives = [
            {
                "model": r["model"],
                "class_name": r["class_name"],
                "display_name": CLASS_INFO.get(r["class_name"], {}).get(
                    "display", r["class_name"].replace("_", " ")
                ),
                "confidence": float(r["confidence"]),
            }
            for r in sorted_results[:5]
        ]

        primary_display = CLASS_INFO.get(best["class_name"], {}).get(
            "display", best["class_name"].replace("_", " ")
        )
        recommendations = recommendation_for_class(best["class_name"])

        return {
            "status": status,
            "message": message,
            "disease": best["class_name"],
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
