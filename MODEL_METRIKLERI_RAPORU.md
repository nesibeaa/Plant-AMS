# 📊 PLANTVILLAGE MODEL METRİKLERİ RAPORU

## 📈 ÖZET

- **Model Tipi:** Multi-Output Classification (Bitki Türü + Sağlık Durumu)
- **Mimari:** ResNet18 Backbone + İki Ayrı Çıktı Kafası
- **Dataset:** PlantVillage Dataset (54,305 görüntü)
- **Eğitim Süresi:** ~12 saat (CPU)
- **Epoch Sayısı:** 10

---

## 🎯 VALİDASYON SONUÇLARI

### Multi-Output Model (Ana Model)

| Metrik | Değer |
|--------|-------|
| **Plant Accuracy** | **99.98%** |
| **Health Accuracy** | **99.69%** |
| **Average Accuracy** | **99.83%** |
| **Training Time** | 42,827.4s (~11.9 saat) |

### Karşılaştırma: Single-Output Modeller

| Model | Accuracy | Training Time |
|-------|----------|---------------|
| **Plant-Only Model** | 99.96% | 40,589.6s (~11.3 saat) |
| **Health-Only Model** | 99.65% | 40,347.4s (~11.2 saat) |
| **Combined Average** | 99.81% | 80,937.0s (~22.5 saat) |

### Performans Karşılaştırması

- **Plant Classification:** Multi-output model **+0.02%** daha iyi
- **Health Classification:** Multi-output model **+0.04%** daha iyi
- **Average:** Multi-output model **+0.02%** daha iyi
- **Zaman Tasarrufu:** Multi-output model **%47 daha hızlı** (tek model vs iki model)

---

## 📉 LOSS DEĞERLERİ

### Multi-Output Model Loss (Epoch Bazında)

Notebook çıktısından alınan son epoch değerleri:

| Epoch | Train Loss | Val Loss | Train Plant Acc | Train Health Acc | Val Plant Acc | Val Health Acc |
|-------|-----------|----------|-----------------|------------------|---------------|----------------|
| 1 | 0.3398 | 0.0972 | 0.9754 | 0.9424 | 0.9967 | 0.9724 |
| 2 | 0.0803 | 0.0409 | 0.9958 | 0.9818 | 0.9980 | 0.9899 |
| 3 | 0.0573 | 0.0327 | 0.9964 | 0.9868 | 0.9989 | 0.9908 |
| 4 | 0.0250 | 0.0169 | 0.9985 | 0.9948 | 0.9994 | 0.9956 |
| 5 | 0.0174 | 0.0158 | 0.9992 | 0.9958 | 0.9994 | 0.9954 |
| 6 | 0.0133 | 0.0145 | 0.9996 | 0.9975 | 0.9993 | 0.9963 |
| 7 | 0.0125 | 0.0129 | 0.9994 | 0.9973 | 0.9996 | 0.9974 |
| 8 | 0.0104 | 0.0129 | 0.9996 | 0.9980 | 0.9996 | 0.9971 |
| 9 | 0.0101 | 0.0119 | 0.9998 | 0.9982 | 0.9991 | 0.9976 |
| **10** | **0.0100** | **0.0123** | **0.9997** | **0.9982** | **0.9998** | **0.9969** |

### Loss Analizi

- **Final Train Loss:** 0.0100
- **Final Val Loss:** 0.0123
- **Overfitting:** Minimal (train ve val loss çok yakın)
- **Convergence:** Epoch 4-5'te yakınsama başladı

---

## 📊 ACCURACY TREND (Epoch Bazında)

### Plant Accuracy (Validation)

| Epoch | Accuracy |
|-------|----------|
| 1 | 99.67% |
| 2 | 99.80% |
| 3 | 99.89% |
| 4 | 99.94% |
| 5 | 99.94% |
| 6 | 99.93% |
| 7 | 99.96% |
| 8 | 99.96% |
| 9 | 99.91% |
| **10** | **99.98%** |

### Health Accuracy (Validation)

| Epoch | Accuracy |
|-------|----------|
| 1 | 97.24% |
| 2 | 98.99% |
| 3 | 99.08% |
| 4 | 99.56% |
| 5 | 99.54% |
| 6 | 99.63% |
| 7 | 99.74% |
| 8 | 99.71% |
| 9 | 99.76% |
| **10** | **99.69%** |

---

## 🔍 CONFUSION MATRIX

### Notlar

- Confusion matrix test seti üzerinde oluşturulmalı
- 14 bitki türü için 14x14 confusion matrix
- 21 sağlık durumu için 21x21 confusion matrix
- Detaylı confusion matrix için test seti değerlendirmesi gerekiyor

### Test Seti Bilgileri

- **Test Seti Boyutu:** 5,431 görüntü
- **Validation Seti Boyutu:** 5,430 görüntü
- **Train Seti Boyutu:** 43,444 görüntü
- **Toplam:** 54,305 görüntü

---

## 📋 DATASET BİLGİLERİ

### Veri Dağılımı

- **Train:** 80% (43,444)
- **Validation:** 10% (5,430)
- **Test:** 10% (5,431)

### Sınıf Dağılımı

- **Bitki Türleri:** 14 adet
- **Sağlık Durumları:** 21 adet
- **Toplam Kombinasyon:** 38 (gerçek dataset'teki kombinasyonlar)

---

## ✅ VALİDASYON YAPILDI MI?

**Evet, validation yapıldı!**

- ✅ Her epoch'ta validation seti üzerinde değerlendirme yapıldı
- ✅ Validation accuracy ve loss değerleri kaydedildi
- ✅ Overfitting kontrolü yapıldı (train/val loss karşılaştırması)
- ⚠️ Test seti üzerinde final değerlendirme yapılabilir (confusion matrix için)

---

## 📝 HOCAYA SUNULACAK ÖZET

### Model Performansı

1. **Accuracy:** 
   - Bitki türü tahmini: **99.98%**
   - Sağlık durumu tahmini: **99.69%**
   - Ortalama: **99.83%**

2. **Loss:**
   - Final Train Loss: **0.0100**
   - Final Val Loss: **0.0123**
   - Overfitting yok (train/val loss yakın)

3. **Validation:**
   - ✅ Her epoch'ta validation yapıldı
   - ✅ 10 epoch boyunca validation accuracy takip edildi
   - ✅ Overfitting kontrolü yapıldı

4. **Confusion Matrix:**
   - Test seti üzerinde oluşturulabilir
   - 14x14 (bitki türleri)
   - 21x21 (sağlık durumları)

### Model Avantajları

- Multi-output yaklaşımı: Tek model ile hem bitki hem sağlık tahmini
- Yüksek accuracy: %99+ performans
- Hızlı eğitim: Single-output modellere göre %47 daha hızlı
- Overfitting yok: Train/val loss dengeli

---

## 🔧 TEST SETİ DEĞERLENDİRMESİ İÇİN

Test seti üzerinde confusion matrix oluşturmak için:

```python
# Test seti üzerinde tahmin yap
# Confusion matrix oluştur
# Classification report çıkar
```

Bu işlem için `generate_model_metrics.py` script'i hazırlandı.

