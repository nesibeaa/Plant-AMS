# 🌱 Bitki Hastalık Tespiti ve IoT İzleme Sistemi

Modern yapay zeka destekli bitki hastalık tespiti ve IoT sensör izleme platformu. PlantVillage veri seti üzerinde eğitilmiş derin öğrenme modelleri kullanarak bitki türü ve sağlık durumunu tespit eder.

## 📋 İçindekiler

- [Özellikler](#-özellikler)
- [Proje Yapısı](#-proje-yapısı)
- [Kurulum](#-kurulum)
- [Kullanım](#-kullanım)
- [Model Detayları](#-model-detayları)
- [API Dokümantasyonu](#-api-dokümantasyonu)
- [Geliştirme](#-geliştirme)
- [Katkıda Bulunma](#-katkıda-bulunma)

## ✨ Özellikler

### 🤖 Yapay Zeka Özellikleri

- **Çoklu Çıktılı Model**: Bitki türü ve sağlık durumunu aynı anda tespit eder
- **PlantVillage Dataset**: 14 bitki türü ve 21 sağlık durumu için eğitilmiş model
- **Yüksek Doğruluk**: 
  - Bitki türü tespiti: %99.98
  - Sağlık durumu tespiti: %99.69
  - Ortalama doğruluk: %99.83
- **Akıllı Görüntü İşleme**: Saliency detection ile bitki bölgesini otomatik bulma
- **Güven Skoru**: Düşük güven skorlarında kullanıcıyı uyarma

### 📱 Mobil Uygulama (Flutter)

- **Çapraz Platform**: iOS, Android ve Web desteği
- **Bitki Analizi**: Fotoğraf çekerek anında hastalık tespiti
- **IoT İzleme**: Sıcaklık, nem ve CO₂ sensör verilerini görüntüleme
- **Grafikler**: Zaman serisi grafikleri ile veri analizi
- **Kullanıcı Kimlik Doğrulama**: Güvenli giriş ve kayıt sistemi
- **Hava Durumu**: Open-Meteo API ile hava durumu bilgisi

### 🌐 Backend API (FastAPI)

- **RESTful API**: Modern ve hızlı API tasarımı
- **Model Metrikleri**: Confusion matrix, precision, recall, F1-score
- **Sensör Yönetimi**: IoT sensör verilerini kaydetme ve sorgulama
- **Aktüatör Kontrolü**: Fan, ısıtıcı ve nemlendirici kontrolü
- **Otomatik Uyarılar**: Eşik değerlerini aşan durumlarda uyarı

### 📊 Veri Analizi

- **Confusion Matrix**: Model performansını görselleştirme
- **Classification Report**: Detaylı metrik raporları
- **Test Seti Değerlendirmesi**: Model doğruluğunu ölçme

## 🏗️ Proje Yapısı

```
aa/
├── app/                          # Flutter mobil/web uygulaması
│   ├── lib/                      # Dart kaynak kodları
│   ├── android/                  # Android platform dosyaları
│   ├── ios/                      # iOS platform dosyaları
│   └── pubspec.yaml              # Flutter bağımlılıkları
│
├── backend/                      # FastAPI Python backend
│   ├── main.py                   # Ana API dosyası
│   ├── plant_classifier.py       # Bitki sınıflandırıcı wrapper
│   ├── plantvillage_classifier.py # PlantVillage multi-output model
│   ├── models/                   # Eğitilmiş model dosyaları
│   │   └── plantvillage_multi.pt # Ana model ağırlıkları
│   └── requirements.txt          # Python bağımlılıkları
│
├── ml/                           # Makine öğrenmesi araçları
│   ├── src/                      # Eğitim scriptleri
│   └── requirements-ml.txt       # ML bağımlılıkları
│
├── PlantVillage-Dataset/         # Veri seti
│   └── raw/                      # Ham görüntüler
│
├── create_confusion_matrix.py     # Confusion matrix oluşturma
├── generate_model_metrics.py      # Model metrikleri raporu
└── README.md                     # Bu dosya
```

## 🚀 Kurulum

### Gereksinimler

- **Python 3.10+**
- **Flutter 3.5+** (mobil uygulama için)
- **PyTorch** (CUDA desteği opsiyonel)
- **SQLite** (veritabanı)

### 1. Backend Kurulumu

```bash
# Backend dizinine git
cd backend

# Python bağımlılıklarını yükle
pip install -r requirements.txt

# Model dosyasının mevcut olduğundan emin ol
# backend/models/plantvillage_multi.pt dosyası gerekli
```

### 2. Flutter Uygulaması Kurulumu

```bash
# Flutter dizinine git
cd app

# Bağımlılıkları yükle
flutter pub get

# iOS için (macOS gerekli)
cd ios && pod install && cd ..

# Android için
# Android Studio ile projeyi aç ve Gradle sync yap
```

### 3. Model Dosyası

Model dosyası (`backend/models/plantvillage_multi.pt`) projeye dahil edilmelidir. Eğer yoksa:

1. `ml/` dizinindeki eğitim scriptlerini kullanarak modeli eğitin
2. Veya önceden eğitilmiş model dosyasını `backend/models/` dizinine ekleyin

## 💻 Kullanım

### Backend'i Başlatma

```bash
# Backend dizininde
cd backend

# Geliştirme modunda başlat
uvicorn main:app --reload --host 127.0.0.1 --port 8000

# Production modunda başlat
uvicorn main:app --host 0.0.0.0 --port 8000 --workers 4
```

Backend başarıyla çalışıyorsa:
- API Dokümantasyonu: http://127.0.0.1:8000/docs
- ReDoc: http://127.0.0.1:8000/redoc
- Health Check: http://127.0.0.1:8000/api/v1/health

### Flutter Uygulamasını Çalıştırma

```bash
# Flutter dizininde
cd app

# Web'de çalıştır
flutter run -d chrome

# iOS simülatörde çalıştır (macOS gerekli)
flutter run -d ios

# Android emülatörde çalıştır
flutter run -d android
```

### Model Metriklerini Oluşturma

```bash
# Confusion matrix oluştur
python create_confusion_matrix.py

# Model metrikleri raporu oluştur
python generate_model_metrics.py
```

## 🤖 Model Detayları

### Model Mimarisi

- **Backbone**: ResNet18
- **Çıktılar**: 
  - Bitki türü (14 sınıf)
  - Sağlık durumu (21 sınıf)
- **Görüntü Boyutu**: 224x224
- **Normalizasyon**: ImageNet mean/std
- **Dropout**: 0.3-0.5 (overfitting önleme)

### Desteklenen Bitki Türleri

1. Apple (Elma)
2. Blueberry (Yaban Mersini)
3. Cherry (Kiraz)
4. Corn (Mısır)
5. Grape (Üzüm)
6. Orange (Turunçgil)
7. Peach (Şeftali)
8. Pepper (Biber)
9. Potato (Patates)
10. Raspberry (Ahududu)
11. Soybean (Soya)
12. Squash (Kabak)
13. Strawberry (Çilek)
14. Tomato (Domates)

### Sağlık Durumları

- **Healthy**: Sağlıklı
- **Bacterial Spot**: Bakteriyel leke
- **Early Blight**: Erken yanıklık
- **Late Blight**: Geç yanıklık
- **Leaf Mold**: Yaprak küfü
- **Septoria Leaf Spot**: Septoria yaprak lekesi
- **Spider Mites**: Kırmızı örümcek
- **Target Spot**: Hedef leke
- **Yellow Leaf Curl Virus**: Sarı yaprak kıvırcık virüsü
- **Mosaic Virus**: Mozaik virüsü
- Ve daha fazlası...

### Model Performansı

| Metrik | Bitki Türü | Sağlık Durumu | Ortalama |
|--------|------------|---------------|----------|
| **Accuracy** | 99.98% | 99.69% | 99.83% |
| **Precision** | ~0.999 | ~0.997 | ~0.998 |
| **Recall** | ~0.999 | ~0.997 | ~0.998 |
| **F1-Score** | ~0.999 | ~0.997 | ~0.998 |

## 📡 API Dokümantasyonu

### Kimlik Doğrulama

```bash
# Kullanıcı kaydı
POST /api/v1/auth/register
{
  "email": "user@example.com",
  "username": "username",
  "password": "password123",
  "full_name": "Full Name"
}

# Giriş
POST /api/v1/auth/login
{
  "username": "username",
  "password": "password123"
}

# Mevcut kullanıcı bilgileri
GET /api/v1/auth/me
Authorization: Bearer <token>
```

### Bitki Analizi

```bash
# Bitki fotoğrafı analiz et
POST /api/v1/analyze-plant
Authorization: Bearer <token>
Content-Type: multipart/form-data
{
  "image": <file>,
  "model": "auto" | "outdoor" | "plantvillage"
}

# Yanıt örneği
{
  "status": "Model Tahmini",
  "disease": "Tomato___Tomato_Bacterial_spot",
  "disease_display": "Tomato • Bacterial Spot",
  "confidence_score": 0.95,
  "health_score": 0.2,
  "health_label": "Riskli",
  "recommendations": [
    "Hastalık ilerlememesi için etkilenen yaprakları budayın...",
    "..."
  ],
  "analysis": {
    "model": "plantvillage",
    "plant": {
      "name": "Tomato",
      "confidence": 0.98
    },
    "health": {
      "status": "Bacterial_spot",
      "confidence": 0.92
    }
  }
}
```

### Model Metrikleri

```bash
# Model performans metriklerini al
GET /api/v1/model-metrics
Authorization: Bearer <token>

# Yanıt örneği
{
  "test_set_size": 5265,
  "accuracy": {
    "plant": 0.9998,
    "health": 0.9969,
    "average": 0.9983
  },
  "confusion_matrices": {
    "plant": {
      "matrix": [[...], [...]],
      "class_names": ["Apple", "Blueberry", ...],
      "shape": [14, 14]
    },
    "health": {
      "matrix": [[...], [...]],
      "class_names": ["Healthy", "Bacterial_spot", ...],
      "shape": [21, 21]
    }
  },
  "classification_report": {
    "plant": {
      "precision": 0.999,
      "recall": 0.999,
      "f1_score": 0.999
    },
    "health": {
      "precision": 0.997,
      "recall": 0.997,
      "f1_score": 0.997
    }
  }
}
```

### IoT Sensörleri

```bash
# Sensör verisi gönder
POST /api/v1/ingest
{
  "sensor_id": "temp-1",
  "type": "temp",
  "value": 22.5,
  "ts": "2024-01-15T14:30:00Z"
}

# Son okumaları al
GET /api/v1/latest

# Okuma geçmişi
GET /api/v1/readings?sensor_id=temp-1&limit=100

# İstatistikler
GET /api/v1/stats/series?sensor=temp&bucket=daily&days=7
```

### Hava Durumu

```bash
# Hava durumu bilgisi
GET /api/v1/weather?city=Istanbul&country_code=TR

# Koordinat ile
GET /api/v1/weather?lat=41.0082&lon=28.9784
```

## 🔧 Geliştirme

### Ortam Değişkenleri

Backend için `.env` dosyası oluşturun:

```bash
# backend/.env
SECRET_KEY=your-secret-key-here
```

### Test

```bash
# Backend testleri
cd backend
pytest

# Flutter testleri
cd app
flutter test
```

### Model Eğitimi

Model eğitimi için `ml/` dizinindeki scriptleri kullanın:

```bash
cd ml
pip install -r requirements-ml.txt
python src/train.py
```

## 📊 Veri Seti

Bu proje [PlantVillage Dataset](https://github.com/spMohanty/PlantVillage-Dataset) kullanmaktadır:

- **Toplam Görüntü**: ~52,000+
- **Bitki Türleri**: 14
- **Sağlık Durumları**: 21
- **Format**: RGB renkli görüntüler
- **Çözünürlük**: Değişken (224x224'e normalize edilir)

## 🐛 Sorun Giderme

### Model yüklenmiyor

- `backend/models/plantvillage_multi.pt` dosyasının mevcut olduğundan emin olun
- Model dosyasının doğru formatta olduğunu kontrol edin

### API hatası

- Backend'in çalıştığından emin olun: `curl http://127.0.0.1:8000/api/v1/health`
- CORS ayarlarını kontrol edin
- Kimlik doğrulama token'ının geçerli olduğundan emin olun

### Flutter bağımlılıkları

```bash
cd app
flutter clean
flutter pub get
```

## 📝 Lisans

Bu proje eğitim ve araştırma amaçlı geliştirilmiştir.

## 👥 Katkıda Bulunma

1. Bu repository'yi fork edin
2. Feature branch oluşturun (`git checkout -b feature/YeniOzellik`)
3. Değişikliklerinizi commit edin (`git commit -am 'Yeni özellik eklendi'`)
4. Branch'inizi push edin (`git push origin feature/YeniOzellik`)
5. Pull Request oluşturun

## 🙏 Teşekkürler

- [PlantVillage Dataset](https://github.com/spMohanty/PlantVillage-Dataset) - Veri seti
- [FastAPI](https://fastapi.tiangolo.com/) - Modern web framework
- [Flutter](https://flutter.dev/) - Çapraz platform framework
- [PyTorch](https://pytorch.org/) - Derin öğrenme framework
- [Open-Meteo](https://open-meteo.com/) - Ücretsiz hava durumu API

## 📧 İletişim

Sorularınız veya önerileriniz için issue açabilirsiniz.

---

⭐ Bu projeyi beğendiyseniz yıldız vermeyi unutmayın!
