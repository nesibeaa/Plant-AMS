#!/usr/bin/env python3
"""
Confusion Matrix'i test etmek için basit script
Backend çalışıyorsa bu script'i çalıştır
"""

import requests
import json

# Backend URL'i (değiştir gerekirse)
BASE_URL = "http://localhost:8000"

# Kullanıcı adı ve şifre (kendi bilgilerini kullan)
USERNAME = "nesibe651@hotmail.com"  # Email veya username
PASSWORD = "123456"  # Kendi şifreni yaz

print("="*70)
print("📊 CONFUSION MATRIX TEST")
print("="*70)

# 1. Login yap
print("\n1️⃣ Login yapılıyor...")
try:
    login_response = requests.post(
        f"{BASE_URL}/api/v1/auth/login",
        json={"username": USERNAME, "password": PASSWORD}
    )
    
    if login_response.status_code != 200:
        print(f"❌ Login başarısız (Status: {login_response.status_code})")
        print(f"   Response: {login_response.text}")
        print("\n💡 İpucu: Önce bir kullanıcı oluşturmalısın:")
        print(f"   python3 -c \"import requests; r = requests.post('{BASE_URL}/api/v1/auth/register', json={{'email': '{USERNAME}', 'password': '{PASSWORD}', 'full_name': 'Test User'}}); print(r.text)\"")
        exit(1)
    
    response_data = login_response.json()
    if "access_token" not in response_data:
        print(f"❌ Token bulunamadı. Response: {response_data}")
        exit(1)
    
    token = response_data["access_token"]
    print("✅ Login başarılı!")
except Exception as e:
    print(f"❌ Login hatası: {e}")
    print(f"   Response: {login_response.text if 'login_response' in locals() else 'N/A'}")
    exit(1)

# 2. Confusion Matrix'i al
print("\n2️⃣ Confusion Matrix alınıyor...")
print("   ⏳ Bu işlem biraz zaman alabilir (5431 görüntü üzerinde tahmin yapılıyor)...")
print("   💡 Lütfen bekleyin...")
headers = {"Authorization": f"Bearer {token}"}

try:
    # Progress için streaming response kullan
    print("   📡 Backend'e istek gönderiliyor...")
    metrics_response = requests.get(
        f"{BASE_URL}/api/v1/model-metrics",
        headers=headers,
        timeout=600  # 10 dakika timeout (5431 görüntü için yeterli)
    )
    print("   ✅ Yanıt alındı!")
except requests.exceptions.Timeout:
    print("   ⏱️ İşlem çok uzun sürdü (5 dakika timeout)")
    print("   💡 Backend'de hata olabilir veya dataset yükleniyor olabilir")
    exit(1)
except Exception as e:
    print(f"   ❌ Hata: {e}")
    exit(1)

if metrics_response.status_code != 200:
    print(f"❌ Hata: {metrics_response.status_code}")
    print(metrics_response.text)
    exit(1)

data = metrics_response.json()

# 3. Sonuçları göster
print("\n" + "="*70)
print("📊 MODEL METRİKLERİ")
print("="*70)

print(f"\n📦 Test Seti: {data['test_set_size']} örnek")

print(f"\n✅ ACCURACY:")
print(f"   Plant: {data['accuracy']['plant']*100:.2f}%")
print(f"   Health: {data['accuracy']['health']*100:.2f}%")
print(f"   Average: {data['accuracy']['average']*100:.2f}%")

print(f"\n📊 CONFUSION MATRIX:")
print(f"   Plant: {data['confusion_matrices']['plant']['shape']} matris")
print(f"   Health: {data['confusion_matrices']['health']['shape']} matris")

print(f"\n📈 CLASSIFICATION REPORT:")
print(f"   Plant - Precision: {data['classification_report']['plant']['precision']:.4f}")
print(f"   Plant - Recall: {data['classification_report']['plant']['recall']:.4f}")
print(f"   Plant - F1-Score: {data['classification_report']['plant']['f1_score']:.4f}")
print(f"   Health - Precision: {data['classification_report']['health']['precision']:.4f}")
print(f"   Health - Recall: {data['classification_report']['health']['recall']:.4f}")
print(f"   Health - F1-Score: {data['classification_report']['health']['f1_score']:.4f}")

# 4. JSON olarak kaydet
with open("confusion_matrix_api_result.json", "w") as f:
    json.dump(data, f, indent=2)

print("\n💾 Sonuçlar kaydedildi: confusion_matrix_api_result.json")
print("="*70)
print("✅ Test tamamlandı!")

