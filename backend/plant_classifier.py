from __future__ import annotations

import threading
from pathlib import Path
from typing import Any, Dict, Optional

import torch
from PIL import Image
from torchvision import transforms
import timm


class PlantClassifier:
    """
    Lazy-loading wrapper around a Torch classification model.
    """

    def __init__(
        self,
        weights_path: Path,
        classes_path: Optional[Path] = None,
    ) -> None:
        self.weights_path = Path(weights_path)
        self.classes_path = Path(classes_path) if classes_path else None
        self._model: Optional[torch.nn.Module] = None
        self._device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        self._classes: Optional[list[str]] = None
        self._mean = (0.485, 0.456, 0.406)
        self._std = (0.229, 0.224, 0.225)
        self._img_size = 384
        self._lock = threading.Lock()

    def is_ready(self) -> bool:
        return self.weights_path.exists()

    def _load_bundle(self) -> Dict[str, Any]:
        if not self.weights_path.exists():
            raise FileNotFoundError(f"Model weights not found at {self.weights_path}")
        return torch.load(self.weights_path, map_location="cpu")

    def _ensure_loaded(self) -> None:
        if self._model is not None and self._classes is not None:
            return
        with self._lock:
            if self._model is not None and self._classes is not None:
                return
            bundle = self._load_bundle()
            class_names = bundle.get("class_names")
            if class_names is None and self.classes_path and self.classes_path.exists():
                import json

                with self.classes_path.open("r", encoding="utf-8") as f:
                    payload = json.load(f)
                    class_names = payload["classes"] if isinstance(payload, dict) else payload
            if class_names is None:
                raise RuntimeError("Class names missing from bundle and classes_path")

            model_name = bundle["model_name"]
            self._img_size = bundle.get("img_size", self._img_size)
            self._mean = tuple(bundle.get("mean", self._mean))
            self._std = tuple(bundle.get("std", self._std))

            model = timm.create_model(model_name, pretrained=False, num_classes=len(class_names))
            model.load_state_dict(bundle["state_dict"])
            model.eval()
            model.to(self._device)

            self._model = model
            self._classes = list(class_names)

    def _preprocess(self, image: Image.Image) -> torch.Tensor:
        tfm = transforms.Compose(
            [
                transforms.Resize((self._img_size, self._img_size)),
                transforms.ToTensor(),
                transforms.Normalize(self._mean, self._std),
            ]
        )
        return tfm(image).unsqueeze(0)

    def predict(self, image: Image.Image) -> Dict[str, Any]:
        self._ensure_loaded()
        assert self._model is not None and self._classes is not None

        tensor = self._preprocess(image).to(self._device)
        with torch.no_grad():
            logits = self._model(tensor)
            probabilities = torch.softmax(logits, dim=1).cpu().numpy()[0]

        top_idx = int(probabilities.argmax())
        return {
            "class_id": top_idx,
            "class_name": self._classes[top_idx],
            "confidence": float(probabilities[top_idx]),
            "probabilities": probabilities.tolist(),
        }

