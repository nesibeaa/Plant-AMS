"""
Evaluation script for trained plant disease classifiers.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import torch
from sklearn.metrics import classification_report
from torch import nn

from .datasets import DATASETS, DatasetConfig, create_dataloaders
from .utils import load_class_names


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Evaluate a trained classifier on the test split")
    parser.add_argument("--dataset", choices=DATASETS.keys(), required=True)
    parser.add_argument("--data-root", type=Path, default=Path("."))
    parser.add_argument("--weights", type=Path, required=True, help="Path to exported .pt weights")
    parser.add_argument("--batch-size", type=int, default=64)
    parser.add_argument("--num-workers", type=int, default=4)
    parser.add_argument("--device", type=str, default="cuda" if torch.cuda.is_available() else "cpu")
    return parser.parse_args()


def prepare_dataset(cfg: DatasetConfig, root: Path) -> DatasetConfig:
    return DatasetConfig(
        name=cfg.name,
        train_dir=root / cfg.train_dir,
        val_dir=root / cfg.val_dir,
        test_dir=cfg.test_dir and root / cfg.test_dir,
        img_size=cfg.img_size,
        mean=cfg.mean,
        std=cfg.std,
    )


def load_export(path: Path) -> tuple:
    import timm

    bundle = torch.load(path, map_location="cpu")
    model = timm.create_model(bundle["model_name"], pretrained=False, num_classes=len(bundle["class_names"]))
    model.load_state_dict(bundle["state_dict"])
    return model, bundle


def main() -> None:
    args = parse_args()
    device = torch.device(args.device)
    cfg = prepare_dataset(DATASETS[args.dataset], args.data_root)
    loaders = create_dataloaders(cfg, batch_size=args.batch_size, num_workers=args.num_workers)
    if "test" not in loaders:
        raise RuntimeError("Dataset does not provide a dedicated test split")

    model, bundle = load_export(args.weights)
    model.to(device)
    model.eval()

    criterion = nn.CrossEntropyLoss()
    running_loss = 0.0
    total = 0

    preds, targets = [], []
    with torch.no_grad():
        for images, labels in loaders["test"]:
            images, labels = images.to(device), labels.to(device)
            outputs = model(images)
            loss = criterion(outputs, labels)
            running_loss += loss.item() * labels.size(0)
            total += labels.size(0)

            preds.extend(outputs.argmax(dim=1).cpu().numpy())
            targets.extend(labels.cpu().numpy())

    loss_avg = running_loss / total
    class_names = bundle.get("class_names") or load_class_names(args.weights.with_suffix(".json"))
    report = classification_report(targets, preds, target_names=class_names, digits=4)

    print("Test loss:", loss_avg)
    print(report)


if __name__ == "__main__":
    main()

