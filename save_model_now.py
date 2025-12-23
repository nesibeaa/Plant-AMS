#!/usr/bin/env python3
"""
Modeli notebook'tan kaydetmek için yardımcı script.
Notebook'taki model_multi, plant_names, status_names değişkenlerini kullanır.
"""

import torch
from pathlib import Path

# Notebook'tan değişkenleri almak için
# Bu script'i notebook içinde çalıştır:
# exec(open('save_model_now.py').read())

try:
    # Model ve değişkenlerin notebook'ta tanımlı olması gerekiyor
    if 'model_multi' not in globals() or 'plant_names' not in globals() or 'status_names' not in globals():
        print("❌ Hata: model_multi, plant_names veya status_names tanımlı değil!")
        print("   Bu script'i notebook içinde çalıştırmalısın (Cell 7'den sonra)")
        exit(1)
    
    print("💾 MODEL KAYDEDİLİYOR...")
    print("="*50)
    
    bundle = {
        "state_dict": model_multi.state_dict(),
        "plant_names": plant_names,
        "status_names": status_names,
        "plant_output_dim": len(plant_names),
        "status_output_dim": len(status_names),
        "img_size": 224,
        "mean": [0.485, 0.456, 0.406],
        "std": [0.229, 0.224, 0.225],
    }
    
    # Doğru yol - proje root'undan
    out_path = Path("backend/models/plantvillage_multi.pt")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    torch.save(bundle, out_path)
    
    print(f"✅ Model başarıyla kaydedildi: {out_path.absolute()}")
    print(f"   Plant classes: {len(plant_names)}")
    print(f"   Status classes: {len(status_names)}")
    print(f"   Model size: {out_path.stat().st_size / (1024*1024):.2f} MB")
    print("="*50)
    
except NameError as e:
    print(f"❌ Hata: {e}")
    print("\n📝 Kullanım:")
    print("   1. Notebook'ta Cell 7'yi çalıştırdıktan sonra")
    print("   2. Yeni bir cell oluştur ve şunu yaz:")
    print("      exec(open('save_model_now.py').read())")
    print("   3. VEYA doğrudan şu kodu çalıştır:")
    print("""
bundle = {
    "state_dict": model_multi.state_dict(),
    "plant_names": plant_names,
    "status_names": status_names,
    "plant_output_dim": len(plant_names),
    "status_output_dim": len(status_names),
    "img_size": 224,
    "mean": [0.485, 0.456, 0.406],
    "std": [0.229, 0.224, 0.225],
}
from pathlib import Path
out_path = Path("backend/models/plantvillage_multi.pt")
out_path.parent.mkdir(parents=True, exist_ok=True)
torch.save(bundle, out_path)
print(f"✅ Model kaydedildi: {out_path.absolute()}")
""")

