#!/usr/bin/env python3
"""
Test seti üzerinde confusion matrix ve detaylı metrikler
"""

import sys
sys.path.insert(0, '.')

import torch
import torch.nn as nn
from torch.utils.data import Dataset, DataLoader
import numpy as np
from sklearn.metrics import confusion_matrix, classification_report, f1_score
import pandas as pd
from pathlib import Path
import os
from PIL import Image
import albumentations as A
from albumentations.pytorch import ToTensorV2

# Notebook'taki sınıfları
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

# Model sınıfı
class MultiOutputModel(nn.Module):
    def __init__(self, plant_output_dim, status_output_dim, dropout=0.3):
        super().__init__()
        import torchvision.models as models
        self.backbone = models.resnet18(weights=None)
        self.backbone.fc = nn.Identity()
        self.dropout = nn.Dropout(dropout)
        self.bn = nn.BatchNorm1d(512)
        self.fc_plant = nn.Linear(512, plant_output_dim)
        self.fc_health = nn.Linear(512, status_output_dim)

    def forward(self, x):
        features = self.backbone(x)
        features = self.bn(features)
        features = self.dropout(features)
        return self.fc_plant(features), self.fc_health(features)

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
    from sklearn.model_selection import train_test_split
    train_df, dummy_df = train_test_split(df, train_size=0.8, stratify=df['labels'], random_state=42)
    val_df, test_df = train_test_split(dummy_df, train_size=0.5, stratify=dummy_df['labels'], random_state=42)
    return train_df.reset_index(drop=True), val_df.reset_index(drop=True), test_df.reset_index(drop=True)

print("="*70)
print("📊 TEST SETİ DEĞERLENDİRMESİ")
print("="*70)

# Model yükle
model_path = Path("backend/models/plantvillage_multi.pt")
bundle = torch.load(model_path, map_location="cpu")

plant_names = bundle.get("plant_names", [])
status_names = bundle.get("status_names", [])

device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
model = MultiOutputModel(len(plant_names), len(status_names))
model.load_state_dict(bundle["state_dict"])
model.eval()
model.to(device)

# Test seti yükle
data_dir = 'PlantVillage-Dataset/raw/color'
df = define_paths(data_dir)
train_df, val_df, test_df = split_df(df)

print(f"\n📦 Dataset:")
print(f"   Train: {len(train_df)}")
print(f"   Val: {len(val_df)}")
print(f"   Test: {len(test_df)}")

test_transform = A.Compose([
    A.Resize(224, 224),
    A.Normalize(mean=(0.485, 0.456, 0.406), std=(0.229, 0.224, 0.225)),
    ToTensorV2()
])

test_dataset = PlantMultiOutputDataset(test_df, transform=test_transform)
test_loader = DataLoader(test_dataset, batch_size=32, shuffle=False, num_workers=0)

# Test
print("\n🔄 Test seti üzerinde tahmin yapılıyor...")
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
plant_acc = np.mean(np.array(all_plant_preds) == np.array(all_plant_labels))
health_acc = np.mean(np.array(all_health_preds) == np.array(all_health_labels))

print(f"\n✅ Test Seti Sonuçları:")
print(f"   Plant Accuracy: {plant_acc*100:.2f}%")
print(f"   Health Accuracy: {health_acc*100:.2f}%")
print(f"   Average Accuracy: {(plant_acc + health_acc)/2*100:.2f}%")

# Confusion Matrix
plant_cm = confusion_matrix(all_plant_labels, all_plant_preds)
health_cm = confusion_matrix(all_health_labels, all_health_preds)

print(f"\n📊 Confusion Matrix:")
print(f"   Plant CM: {plant_cm.shape} (14x14)")
print(f"   Health CM: {health_cm.shape} (21x21)")

# Classification Report
plant_report = classification_report(all_plant_labels, all_plant_preds, target_names=plant_names, output_dict=True)
health_report = classification_report(all_health_labels, all_health_preds, target_names=status_names, output_dict=True)

print(f"\n📈 Classification Report Özeti:")
print(f"   Plant - Precision: {plant_report['weighted avg']['precision']:.4f}")
print(f"   Plant - Recall: {plant_report['weighted avg']['recall']:.4f}")
print(f"   Plant - F1-Score: {plant_report['weighted avg']['f1-score']:.4f}")
print(f"   Health - Precision: {health_report['weighted avg']['precision']:.4f}")
print(f"   Health - Recall: {health_report['weighted avg']['recall']:.4f}")
print(f"   Health - F1-Score: {health_report['weighted avg']['f1-score']:.4f}")

# Kaydet
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
    }
}

import json
with open("test_set_metrics.json", "w") as f:
    json.dump(results, f, indent=2)

print("\n💾 Sonuçlar kaydedildi: test_set_metrics.json")
print("="*70)

