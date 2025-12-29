# 📱 iPhone Sunum Hazırlık Kontrol Listesi

## ✅ Sunum Öncesi Kontroller

### 1. Backend Durumu
- [ ] Backend sunucusu çalışıyor mu?
- [ ] Backend URL'i doğru mu? (Ayarlar > Backend URL)
- [ ] iPhone ve backend aynı ağda mı? (Wi-Fi)
- [ ] Backend'e iPhone'dan erişilebiliyor mu?

### 2. iPhone'a Yükleme
```bash
cd app
flutter build ios
# Xcode ile aç
open ios/Runner.xcworkspace
# iPhone'a yükle (Xcode'dan)
```

### 3. Test Edilecek Özellikler

#### ✅ Çalışan Özellikler (Backend Gerekmez)
- [x] Bitki listesi görüntüleme
- [x] Bitki kaydetme
- [x] Bitki detay sayfası
- [x] Analiz geçmişi görüntüleme
- [x] UI ve navigasyon

#### ⚠️ Backend Gerektiren Özellikler
- [ ] **Bitki fotoğraf analizi** (EN ÖNEMLİ!)
- [ ] Sensor verileri (Ana sayfa kartları)
- [ ] Hava durumu
- [ ] Grafikler (24 saat / 7 gün)
- [ ] Kontrol paneli

### 4. Sunum Senaryosu

#### Senaryo 1: Backend Çalışıyorsa
1. ✅ Ana sayfayı göster (sensor verileri, hava durumu)
2. ✅ Grafikler sayfasını göster
3. ✅ **Bitki analizi sayfası** - Fotoğraf yükle ve analiz et
4. ✅ Analiz sonuçlarını göster (bakım önerileri, tesis gereksinimleri)
5. ✅ Bitkiyi kaydet
6. ✅ Bitkilerim sayfasında kaydedilen bitkiyi göster
7. ✅ Bitki detay sayfasını göster (timeline, bakım bilgileri)

#### Senaryo 2: Backend Çalışmıyorsa
- ⚠️ Bitki analizi çalışmayacak
- ⚠️ Sensor verileri gösterilmeyecek
- ⚠️ Hava durumu gösterilmeyecek
- ✅ Bitki listesi ve detay sayfaları çalışacak

## 🔧 Hızlı Çözümler

### Backend URL'i Değiştirme
1. Uygulamayı aç
2. Ayarlar sayfasına git
3. "Backend URL" ayarını değiştir
4. Uygulamayı yeniden başlat

### Backend Test
```bash
# Backend'in çalıştığını test et
curl http://YOUR_BACKEND_IP:8000/api/v1/latest
```

### iPhone IP Kontrolü
- iPhone ve bilgisayar aynı Wi-Fi'de olmalı
- Backend URL: `http://BILGISAYAR_IP:8000`
- Mac'te IP bulma: `ifconfig | grep "inet " | grep -v 127.0.0.1`

## 📝 Sunum İçin Notlar

### Vurgulanacak Özellikler
1. **Bitki Analizi**: AI destekli hastalık tespiti
2. **Bakım Önerileri**: Bitki ve hastalığa özel detaylı öneriler
3. **Tesis Gereksinimleri**: CO2, sıcaklık, nem, toprak bilgileri
4. **Timeline**: Bitki sağlık geçmişi takibi
5. **Türkçe Arayüz**: Tüm içerik Türkçe

### Potansiyel Sorunlar
- Backend bağlantı hatası → Backend URL'i kontrol et
- Fotoğraf yüklenmiyor → Kamera izinlerini kontrol et
- Analiz çalışmıyor → Backend'in çalıştığını doğrula

## 🚀 Son Kontrol
- [ ] Uygulama iPhone'da yüklü
- [ ] Backend çalışıyor
- [ ] Wi-Fi bağlantısı aktif
- [ ] Test fotoğrafı hazır
- [ ] Sunum senaryosu hazır

