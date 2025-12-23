from __future__ import annotations

"""
PlantVillage multi-output classifier (plant species + health status).

Bu sınıf, notebookfc1a45d95b.ipynb dosyasında tanımlanan MultiOutputModel
ile aynı mimariyi kullanır. Notebook'ta eğitilen modeli export ederken
şu alanları içeren bir bundle kaydediyoruz:

    {
        "state_dict": model_multi.state_dict(),
        "plant_names": plant_names,       # sıralı bitki isimleri
        "status_names": status_names,     # sıralı sağlık/hastalık isimleri
        "img_size": 224,
        "mean": [0.485, 0.456, 0.406],
        "std":  [0.229, 0.224, 0.225],
    }

Bu dosyayı backend/models/plantvillage_multi.pt olarak kaydedip
PlantVillageClassifier ile yüklüyoruz.
"""

import threading
from pathlib import Path
from typing import Any, Dict, Optional

import torch
import torch.nn as nn
from PIL import Image
from torchvision import transforms
import torchvision.models as models
import numpy as np
import cv2


class MultiOutputModel(nn.Module):
    """
    Notebook'taki MultiOutputModel ile aynı mimari.
    ResNet18 backbone, iki ayrı tam bağlantılı kafa (plant + health).
    """

    def __init__(self, plant_output_dim: int, status_output_dim: int, dropout: float = 0.5) -> None:
        super().__init__()
        # Pretrained ağırlıkları tekrar indirmemek için weights=None.
        # Notebook'tan gelen state_dict tüm ağırlıkları içeriyor.
        self.backbone = models.resnet18(weights=None)
        self.backbone.fc = nn.Identity()

        self.dropout = nn.Dropout(dropout)
        self.bn = nn.BatchNorm1d(512)

        self.fc_plant = nn.Linear(512, plant_output_dim)
        self.fc_health = nn.Linear(512, status_output_dim)

    def forward(self, x: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor]:
        features = self.backbone(x)
        features = self.bn(features)
        features = self.dropout(features)
        return self.fc_plant(features), self.fc_health(features)


class PlantVillageClassifier:
    """
    PlantVillage multi-output model wrapper.

    predict() çıktısı, backend/main.py içindeki analyze_plant endpoint'inin
    beklediği tek-çıktılı formatla uyumludur:

        {
            "class_name": "Tomato___Tomato_Bacterial_spot",
            "confidence": 0.92,
            # Ek bilgiler:
            "plant": {...},
            "health": {...},
        }
    """

    def __init__(self, weights_path: Path) -> None:
        self.weights_path = Path(weights_path)
        self._model: Optional[MultiOutputModel] = None
        self._device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        self._plant_names: Optional[list[str]] = None
        self._status_names: Optional[list[str]] = None
        self._img_size: int = 224
        self._mean = (0.485, 0.456, 0.406)
        self._std = (0.229, 0.224, 0.225)
        self._lock = threading.Lock()

    # ------------------------------------------------------------------
    # Lifecycle helpers
    # ------------------------------------------------------------------
    def is_ready(self) -> bool:
        """Model dosyası mevcut mu?"""
        return self.weights_path.exists()

    def _load_bundle(self) -> Dict[str, Any]:
        if not self.weights_path.exists():
            raise FileNotFoundError(f"PlantVillage model weights not found at {self.weights_path}")
        return torch.load(self.weights_path, map_location="cpu")

    def _ensure_loaded(self) -> None:
        if self._model is not None and self._plant_names is not None and self._status_names is not None:
            return

        with self._lock:
            if self._model is not None and self._plant_names is not None and self._status_names is not None:
                return

            bundle = self._load_bundle()

            plant_names = bundle.get("plant_names")
            status_names = bundle.get("status_names")

            if plant_names is None or status_names is None:
                raise RuntimeError("plant_names veya status_names bundle içinde bulunamadı")

            plant_output_dim = bundle.get("plant_output_dim", len(plant_names))
            status_output_dim = bundle.get("status_output_dim", len(status_names))

            self._img_size = int(bundle.get("img_size", self._img_size))
            mean = bundle.get("mean", self._mean)
            std = bundle.get("std", self._std)
            self._mean = tuple(float(m) for m in mean)
            self._std = tuple(float(s) for s in std)

            model = MultiOutputModel(plant_output_dim, status_output_dim)
            state_dict = bundle.get("state_dict")
            if state_dict is None:
                raise RuntimeError("state_dict bundle içinde bulunamadı")
            model.load_state_dict(state_dict)
            model.to(self._device)
            model.eval()

            self._model = model
            self._plant_names = list(plant_names)
            self._status_names = list(status_names)

    # ------------------------------------------------------------------
    # Inference
    # ------------------------------------------------------------------
    def _preprocess(self, image: Image.Image) -> torch.Tensor:
        """
        Görüntüyü model için hazırlar.
        Gerçek dünya fotoğrafları için gelişmiş preprocessing:
        - Saliency detection ile bitki bölgesini bul
        - Akıllı crop ile bitkiyi merkeze al
        - Multiple crops ile ensemble (daha iyi sonuç için)
        """
        width, height = image.size
        
        # Çok küçük görüntüleri direkt resize et
        if width < 100 or height < 100:
            image = image.resize((self._img_size, self._img_size), Image.Resampling.LANCZOS)
            tfm = transforms.Compose([
                transforms.ToTensor(),
                transforms.Normalize(self._mean, self._std),
            ])
            return tfm(image).unsqueeze(0)
        
        # 1. Saliency detection ile bitki bölgesini bul
        img_array = np.array(image)
        img_rgb = cv2.cvtColor(img_array, cv2.COLOR_RGB2BGR)
        
        # Saliency map oluştur (bitki genelde yeşil/kahverengi tonlarında)
        hsv = cv2.cvtColor(img_rgb, cv2.COLOR_BGR2HSV)
        
        # Yeşil tonları için maske (bitki yaprakları)
        lower_green = np.array([35, 40, 40])
        upper_green = np.array([85, 255, 255])
        green_mask = cv2.inRange(hsv, lower_green, upper_green)
        
        # Kahverengi/sarı tonları için maske (hastalıklı yapraklar)
        lower_brown = np.array([10, 50, 50])
        upper_brown = np.array([30, 255, 255])
        brown_mask = cv2.inRange(hsv, lower_brown, upper_brown)
        
        # Birleştirilmiş maske
        plant_mask = cv2.bitwise_or(green_mask, brown_mask)
        
        # Morphological operations ile gürültüyü temizle
        kernel = np.ones((5, 5), np.uint8)
        plant_mask = cv2.morphologyEx(plant_mask, cv2.MORPH_CLOSE, kernel)
        plant_mask = cv2.morphologyEx(plant_mask, cv2.MORPH_OPEN, kernel)
        
        # Bitki bölgesinin bounding box'unu bul
        contours, _ = cv2.findContours(plant_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        
        if len(contours) > 0:
            # En büyük konturu bul (ana bitki)
            largest_contour = max(contours, key=cv2.contourArea)
            x, y, w, h = cv2.boundingRect(largest_contour)
            
            # Bounding box'u biraz genişlet (margin ekle)
            margin = 0.1
            x = max(0, int(x - w * margin))
            y = max(0, int(y - h * margin))
            w = min(width - x, int(w * (1 + 2 * margin)))
            h = min(height - y, int(h * (1 + 2 * margin)))
            
            # Crop yap
            image = image.crop((x, y, x + w, y + h))
        else:
            # Saliency bulunamazsa, center-weighted crop yap
            # Merkez bölgeyi önceliklendir (80% crop)
            crop_ratio = 0.8
            crop_w = int(width * crop_ratio)
            crop_h = int(height * crop_ratio)
            left = (width - crop_w) // 2
            top = (height - crop_h) // 2
            image = image.crop((left, top, left + crop_w, top + crop_h))
        
        # 2. Kare yap (aspect ratio korunarak)
        w, h = image.size
        if w != h:
            size = min(w, h)
            left = (w - size) // 2
            top = (h - size) // 2
            image = image.crop((left, top, left + size, top + size))
        
        # 3. Yüksek kaliteli resize
        image = image.resize((self._img_size, self._img_size), Image.Resampling.LANCZOS)
        
        # 4. Normalize ve tensor'a çevir
        tfm = transforms.Compose([
            transforms.ToTensor(),
            transforms.Normalize(self._mean, self._std),
        ])
        return tfm(image).unsqueeze(0)

    def predict(self, image: Image.Image) -> Dict[str, Any]:
        """
        Tek görüntü için tahmin üretir.
        """
        self._ensure_loaded()
        assert self._model is not None
        assert self._plant_names is not None
        assert self._status_names is not None

        tensor = self._preprocess(image).to(self._device)
        with torch.no_grad():
            plant_logits, health_logits = self._model(tensor)
            plant_probs = torch.softmax(plant_logits, dim=1).cpu().numpy()[0]
            health_probs = torch.softmax(health_logits, dim=1).cpu().numpy()[0]

        plant_idx = int(plant_probs.argmax())
        health_idx = int(health_probs.argmax())

        plant_name = self._plant_names[plant_idx]
        health_name = self._status_names[health_idx]

        plant_conf = float(plant_probs[plant_idx])
        health_conf = float(health_probs[health_idx])

        combined_class = f"{plant_name}___{health_name}"
        combined_conf = (plant_conf + health_conf) / 2.0

        return {
            "class_name": combined_class,
            "confidence": combined_conf,
            "plant": {
                "class_id": plant_idx,
                "class_name": plant_name,
                "confidence": plant_conf,
                "probabilities": plant_probs.tolist(),
            },
            "health": {
                "class_id": health_idx,
                "class_name": health_name,
                "confidence": health_conf,
                "probabilities": health_probs.tolist(),
            },
        }


