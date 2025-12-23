#!/usr/bin/env python3
"""
Model metriklerini çıkarır: Loss, Accuracy, Confusion Matrix
"""

import sys
sys.path.insert(0, '.')

import torch
import torch.nn as nn
from torch.utils.data import DataLoader
import numpy as np
from sklearn.metrics import confusion_matrix, classification_report, f1_score
import pandas as pd
from pathlib import Path
import json

# Notebook'taki sınıfları import et
from backend.plantvillage_classifier import MultiOutputModel, PlantVillageClassifier
from PIL import Image
import albumentations as A
from albumentations.pytorch import ToTensorV2

print("="*70)
print("📊 MODEL METRİKLERİ RAPORU")
print("="*70)

# 1. Model yükle
print("\n1️⃣ Model yükleniyor...")
model_path = Path("backend/models/plantvillage_multi.pt")
bundle = torch.load(model_path, map_location="cpu")

plant_names = bundle.get("plant_names", [])
status_names = bundle.get("status_names", [])

print(f"   ✅ Bitki türleri: {len(plant_names)}")
print(f"   ✅ Sağlık durumları: {len(status_names)}")

# Model oluştur
device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
model = MultiOutputModel(len(plant_names), len(status_names))
model.load_state_dict(bundle["state_dict"])
model.eval()
model.to(device)

# 2. Notebook'taki eğitim sonuçlarını çıkar
print("\n2️⃣ Eğitim Sonuçları (Notebook çıktısından):")
print("-"*70)

# Kullanıcının daha önce paylaştığı sonuçlardan:
print("\n📈 MULTI-OUTPUT MODEL:")
print(f"   • Plant Accuracy: 99.98%")
print(f"   • Health Accuracy: 99.69%")
print(f"   • Average Accuracy: 99.83%")
print(f"   • Training Time: 42827.4s (~11.9 saat)")

print("\n📈 PLANT-ONLY MODEL:")
print(f"   • Accuracy: 99.96%")
print(f"   • Training Time: 40589.6s (~11.3 saat)")

print("\n📈 HEALTH-ONLY MODEL:")
print(f"   • Accuracy: 99.65%")
print(f"   • Training Time: 40347.4s (~11.2 saat)")

# 3. Test seti üzerinde değerlendirme
print("\n3️⃣ Test Seti Değerlendirmesi...")
print("-"*70)

# Dataset sınıfını yeniden tanımla (notebook'tan)
class PlantMultiOutputDataset:
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

# Test seti yükle
try:
    from sklearn.model_selection import train_test_split
    import pandas as pd
    import os
    
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
    
    data_dir = 'PlantVillage-Dataset/raw/color'
    if Path(data_dir).exists():
        df = define_paths(data_dir)
        train_df, val_df, test_df = split_df(df)
        
        print(f"   Test seti: {len(test_df)} örnek")
        
        # Test transform
        test_transform = A.Compose([
            A.Resize(224, 224),
            A.Normalize(mean=(0.485, 0.456, 0.406), std=(0.229, 0.224, 0.225)),
            ToTensorV2()
        ])
        
        test_dataset = PlantMultiOutputDataset(test_df, transform=test_transform)
        test_loader = DataLoader(test_dataset, batch_size=32, shuffle=False, num_workers=0)
        
        # Test seti üzerinde tahmin
        print("   🔄 Test seti üzerinde tahmin yapılıyor...")
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
        
        # Accuracy hesapla
        plant_acc = np.mean(np.array(all_plant_preds) == np.array(all_plant_labels))
        health_acc = np.mean(np.array(all_health_preds) == np.array(all_health_labels))
        
        print(f"\n   ✅ Test Seti Sonuçları:")
        print(f"      • Plant Accuracy: {plant_acc*100:.2f}%")
        print(f"      • Health Accuracy: {health_acc*100:.2f}%")
        print(f"      • Average Accuracy: {(plant_acc + health_acc)/2*100:.2f}%")
        
        # Confusion Matrix
        print("\n4️⃣ Confusion Matrix Oluşturuluyor...")
        print("-"*70)
        
        plant_cm = confusion_matrix(all_plant_labels, all_plant_preds)
        health_cm = confusion_matrix(all_health_labels, all_health_preds)
        
        print(f"\n   📊 Plant Confusion Matrix: {plant_cm.shape}")
        print(f"   📊 Health Confusion Matrix: {health_cm.shape}")
        
        # Classification Report
        print("\n5️⃣ Classification Report:")
        print("-"*70)
        
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
        
        print("\n   🌱 Plant Classification - Özet:")
        print(f"      • Precision (Ortalama): {plant_report['weighted avg']['precision']:.4f}")
        print(f"      • Recall (Ortalama): {plant_report['weighted avg']['recall']:.4f}")
        print(f"      • F1-Score (Ortalama): {plant_report['weighted avg']['f1-score']:.4f}")
        
        print("\n   🏥 Health Classification - Özet:")
        print(f"      • Precision (Ortalama): {health_report['weighted avg']['precision']:.4f}")
        print(f"      • Recall (Ortalama): {health_report['weighted avg']['recall']:.4f}")
        print(f"      • F1-Score (Ortalama): {health_report['weighted avg']['f1-score']:.4f}")
        
        # Sonuçları kaydet
        results = {
            "test_accuracy": {
                "plant": float(plant_acc),
                "health": float(health_acc),
                "average": float((plant_acc + health_acc) / 2)
            },
            "confusion_matrices": {
                "plant": plant_cm.tolist(),
                "health": health_cm.tolist()
            },
            "classification_reports": {
                "plant": plant_report,
                "health": health_report
            },
            "class_names": {
                "plants": plant_names,
                "statuses": status_names
            }
        }
        
        with open("model_metrics.json", "w") as f:
            json.dump(results, f, indent=2)
        
        print("\n   💾 Detaylı metrikler kaydedildi: model_metrics.json")
        
    else:
        print("   ⚠️ Dataset bulunamadı, sadece eğitim sonuçları gösteriliyor")
        
except Exception as e:
    print(f"   ⚠️ Test seti değerlendirmesi başarısız: {e}")
    import traceback
    traceback.print_exc()

print("\n" + "="*70)
print("✅ Rapor tamamlandı!")
print("="*70)

