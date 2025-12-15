# AgriSmart IoT Monitoring System 🍄

Modern bir IoT sensör izleme ve kontrol sistemi. Mantar yetiştiriciliği için tasarlanmış, ancak her türlü iklim kontrol sistemine uyarlanabilir.

## 🏗️ Proje Yapısı

```
aa/
├── app/                    # Flutter mobil/web uygulaması
├── backend/               # FastAPI Python backend
├── tools/                 # Simülatör ve yardımcı araçlar
├── web/                   # HTML5 dashboard
└── app.db                 # SQLite veritabanı
```

## 🚀 Hızlı Başlangıç

### Gereksinimler
- **Python 3.12+**
- **Flutter 3.35+** (Dart 3.9.2+)
- **Chrome** veya **Safari**

### 1️⃣ Backend'i Başlat

```bash
# Python bağımlılıklarını yükle
pip3 install fastapi uvicorn sqlmodel pydantic

# Backend'i başlat (port 8000)
cd /Users/nesibealatas/Desktop/aa
uvicorn backend.main:app --reload --host 127.0.0.1 --port 8000
```

Backend başarıyla çalışıyorsa:
```
INFO:     Application startup complete.
INFO:     Uvicorn running on http://127.0.0.1:8000
```

### 2️⃣ (Opsiyonel) Sensör Simülatörünü Çalıştır

```bash
cd tools
python3 simulate.py

# Hızlı gönderim için interval ayarla
python3 simulate.py 1.0   # 1 saniye
python3 simulate.py 0.5   # 0.5 saniye
```

Simülatör her 3 saniyede bir sıcaklık, nem ve CO₂ verisi gönderir.

### 3️⃣ Web Dashboard'u Aç

**Seçenek 1: Canlı HTML Dashboard**
```bash
# Chrome veya Safari ile aç
open web/index.html     # Dashboard
open web/stats.html     # İstatistikler
```

**Seçenek 2: Flutter Web Uygulaması**
```bash
cd app
flutter run -d chrome   # Chrome'da çalıştır
flutter run -d safari   # Safari'de çalıştır
```

### 4️⃣ API Endpoints'i Test Et

```bash
# Health check
curl http://127.0.0.1:8000/api/v1/health

# Son okumalar
curl http://127.0.0.1:8000/api/v1/latest

# Son 100 okuma
curl http://127.0.0.1:8000/api/v1/readings

# Uyarılar
curl http://127.0.0.1:8000/api/v1/alerts

# Fan durumu
curl http://127.0.0.1:8000/api/v1/actuator/fan

# Günlük istatistikler (son 7 gün)
curl "http://127.0.0.1:8000/api/v1/stats/series?sensor=temp&bucket=daily&days=7"

# Saatlik istatistikler (son 24 saat)
curl "http://127.0.0.1:8000/api/v1/stats/series?sensor=temp&bucket=hourly&hours=24"
```

## 📊 Özellikler

### Sensörler
- **Sıcaklık** (`temp-1`): Hedef: 18-24°C
- **Nem** (`hum-1`): Hedef: 85-95%
- **CO₂** (`co2-1`): Max: 1500 ppm

### Otomasyon
- **Auto Fan**: Eşik dışı değerlerde otomatik açılır
- **Normal Streak**: 5 normal okuma sonrası otomatik kapanır
- **Manual Override**: Kullanıcı manuel olarak fan'ı kontrol edebilir

### UI
- **Flutter App**: iOS/Android/Web için modern mobil UI
- **HTML Dashboard**: Lightweight, Chart.js ile grafikler
- **Canlı Akış**: Anlık veri izleme
- **Grafikler**: Saatlik ve günlük istatistikler

## 🔧 Yapılandırma

### Eşik Değerleri Değiştirme
```python
# backend/main.py
THRESHOLDS = {
    "temp":     {"min": 18.0, "max": 24.0},
    "humidity": {"min": 85.0, "max": 95.0},
    "co2":      {"max": 1500.0},
}
```

### API URL'i Değiştirme (Flutter)
Uygulama içinde **Ayarlar** sekmesinden API URL'i değiştirebilirsiniz.

## 📱 Mobil Uygulama (Flutter)

### Ana Sayfa
- Sıcaklık, Nem, CO₂ göstergeleri
- Renk kodlu durum rozetleri

### Grafik Sayfası
- 24 saatlik zaman serisi grafikleri
- Her sensör için ayrı grafikler

### Kontrol Sayfası
- Fan, Isıtıcı, Nemlendirici kontrolü

### Ayarlar Sayfası
- API URL yapılandırması
- Ayarlar kalıcı olarak kaydedilir

## 🌐 Web Dashboard

### Dashboard (`index.html`)
- Canlı KPIs
- Üç ayrı grafik (temp/humidity/co2)
- Fan kontrolü
- Canlı veri akışı
- Uyarılar tablosu
- Otomatik yenileme (10 saniye)

### İstatistikler (`stats.html`)
- Günlük ortalamalar (son 7 gün)
- Saatlik ortalamalar (son 24 saat)
- Fan geçmişi

## 🗄️ Veritabanı

### Tablolar
- **reading**: Tüm sensör okumaları
- **alert**: Uyarılar ve bilgilendirmeler
- **fan_event**: Fan açma/kapama olayları

### Veritabanı Görüntüleme
```bash
# VS Code SQLite extension kullan
# veya SQLite CLI ile
sqlite3 app.db

.tables
SELECT * FROM reading ORDER BY ts DESC LIMIT 10;
SELECT * FROM alert ORDER BY ts DESC LIMIT 10;
SELECT * FROM fan_event ORDER BY ts DESC LIMIT 10;
```

## 🐛 Sorun Giderme

### Backend başlamıyor
```bash
# Port kontrolü
lsof -i :8000

# Process'i durdur
pkill -f uvicorn
```

### Flutter bağımlılıkları kurulamıyor
```bash
cd app
flutter clean
flutter pub get
```

### Veri görünmüyor
1. Simülatörün çalıştığından emin olun
2. Backend health check yapın
3. Veritabanında veri olup olmadığını kontrol edin

### CORS hatası (web)
Backend zaten CORS'u etkinleştirmiş durumda. Değilse:
```python
# backend/main.py
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
```

## 📚 API Dokümantasyonu

Backend çalışırken Swagger UI:
```
http://127.0.0.1:8000/docs
```

ReDoc:
```
http://127.0.0.1:8000/redoc
```

## 🎯 Kullanım Senaryoları

### Senaryo 1: İlk Test
```bash
# Terminal 1: Backend
uvicorn backend.main:app --reload

# Terminal 2: Simülatör
python3 tools/simulate.py

# Terminal 3: Web Dashboard
open web/index.html
```

### Senaryo 2: Flutter App
```bash
# Terminal 1: Backend
uvicorn backend.main:app --reload

# Terminal 2: Flutter
cd app && flutter run -d chrome
```

### Senaryo 3: Gerçek Sensörler
Backend'e POST isteği gönderin:
```bash
curl -X POST http://127.0.0.1:8000/api/v1/ingest \
  -H "Content-Type: application/json" \
  -d '{
    "sensor_id": "temp-1",
    "type": "temp",
    "value": 22.5,
    "ts": "2024-01-15T14:30:00Z"
  }'
```

## 📝 Geliştirme Notları

- **Mock Mode**: Flutter uygulamasında backend bağlantısını test etmek için `MOCK_MODE = true` kullanın
- **Timezone**: Tüm timestamp'ler UTC formatında saklanır
- **Cache**: Web arayüzünde cache kontrolü `no-store` ile yapılır
- **Database**: SQLite dosya bazlı, taşınabilir

## 🔒 Güvenlik Notları

- Üretimde CORS'u kısıtlayın (`allow_origins=["*"]` yerine)
- API anahtarı/authentication ekleyin
- HTTPS kullanın
- Veritabanı yedekleme stratejisi oluşturun

## 📦 Dağıtım

### Backend
```bash
# Production için
uvicorn backend.main:app --host 0.0.0.0 --port 8000 --workers 4
```

### Flutter Web
```bash
cd app
flutter build web
# Çıktı: app/build/web/
```

## 🤝 Katkıda Bulunma

1. Fork edin
2. Branch oluşturun (`git checkout -b feature/YeniOzellik`)
3. Commit edin (`git commit -am 'Yeni özellik ekle'`)
4. Push edin (`git push origin feature/YeniOzellik`)
5. Pull Request açın

## 📄 Lisans

Bu proje eğitim amaçlı geliştirilmiştir.

## 👤 Yazar

AgriSmart IoT Team

## 🙏 Teşekkürler

- FastAPI ekibi
- Flutter ekibi
- Chart.js

