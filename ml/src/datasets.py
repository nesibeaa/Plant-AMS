"""
Dataset utilities shared across training and evaluation scripts.
"""

import argparse
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Optional, Tuple

import torch
from torch.utils.data import DataLoader, WeightedRandomSampler
from torchvision import datasets, transforms

from .utils import iter_class_dirs, save_json


@dataclass
class DatasetConfig:
    name: str
    train_dir: Path
    val_dir: Path
    test_dir: Optional[Path] = None
    img_size: int = 384
    mean: Tuple[float, float, float] = (0.485, 0.456, 0.406)
    std: Tuple[float, float, float] = (0.229, 0.224, 0.225)

    @property
    def class_names(self) -> Tuple[str, ...]:
        return tuple(iter_class_dirs(self.train_dir))


def build_transforms(cfg: DatasetConfig, *, train: bool) -> transforms.Compose:
    if train:
        return transforms.Compose(
            [
                transforms.RandomResizedCrop(cfg.img_size, scale=(0.75, 1.0), ratio=(0.9, 1.1)),
                transforms.RandomHorizontalFlip(),
                transforms.RandomRotation(25),
                transforms.ColorJitter(brightness=0.25, contrast=0.25, saturation=0.2, hue=0.05),
                transforms.RandomPerspective(distortion_scale=0.3, p=0.4),
                transforms.ToTensor(),
                transforms.Normalize(cfg.mean, cfg.std),
                transforms.RandomErasing(p=0.4, scale=(0.02, 0.08)),
            ]
        )
    return transforms.Compose(
        [
            transforms.Resize((cfg.img_size, cfg.img_size)),
            transforms.ToTensor(),
            transforms.Normalize(cfg.mean, cfg.std),
        ]
    )


def create_dataloaders(
    cfg: DatasetConfig,
    *,
    batch_size: int = 32,
    num_workers: int = 4,
    use_weighted_sampler: bool = False,
) -> Dict[str, DataLoader]:
    train_tfms = build_transforms(cfg, train=True)
    val_tfms = build_transforms(cfg, train=False)

    train_ds = datasets.ImageFolder(cfg.train_dir, transform=train_tfms)
    val_ds = datasets.ImageFolder(cfg.val_dir, transform=val_tfms)

    test_ds = None
    if cfg.test_dir and cfg.test_dir.exists():
        test_ds = datasets.ImageFolder(cfg.test_dir, transform=val_tfms)

    sampler = None
    if use_weighted_sampler:
        targets = torch.tensor(train_ds.targets, dtype=torch.long)
        class_counts = torch.bincount(targets, minlength=len(train_ds.classes)).float()
        class_counts[class_counts == 0] = 1.0
        class_weights = 1.0 / class_counts
        sample_weights = class_weights[targets]
        sample_weights = sample_weights + 1e-6  # tüm örnekler pozitif ağırlık alsın
        sampler = WeightedRandomSampler(sample_weights, num_samples=len(sample_weights), replacement=True)

    loaders = {
        "train": DataLoader(
            train_ds,
            batch_size=batch_size,
            shuffle=sampler is None,
            sampler=sampler,
            num_workers=num_workers,
            pin_memory=True,
        ),
        "val": DataLoader(val_ds, batch_size=batch_size, shuffle=False, num_workers=num_workers, pin_memory=True),
    }
    if test_ds is not None:
        loaders["test"] = DataLoader(test_ds, batch_size=batch_size, shuffle=False, num_workers=num_workers, pin_memory=True)
    return loaders


DATASETS = {
    "indoor": DatasetConfig(
        name="indoor",
        train_dir=Path("indoor/train"),
        val_dir=Path("indoor/valid"),
        test_dir=Path("indoor/test"),
    ),
    "outdoor": DatasetConfig(
        name="outdoor",
        train_dir=Path("outdoor/New Plant Diseases Dataset(Augmented)/New Plant Diseases Dataset(Augmented)/train"),
        val_dir=Path("outdoor/New Plant Diseases Dataset(Augmented)/New Plant Diseases Dataset(Augmented)/valid"),
    ),
}


def scan_and_write_class_map(scan_root: Path, output_path: Path) -> None:
    classes = iter_class_dirs(scan_root)
    payload = {"source": str(scan_root), "classes": classes}
    save_json(payload, output_path)
    print(f"[✓] Found {len(classes)} classes. Written to {output_path}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Dataset utilities")
    parser.add_argument("--scan", type=Path, help="Directory to scan for class names")
    parser.add_argument("--output", type=Path, help="Where to write JSON class map")
    args = parser.parse_args()

    if args.scan and args.output:
        scan_and_write_class_map(args.scan, args.output)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()

