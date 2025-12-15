"""
Training entrypoint for plant health classification models.
"""

from __future__ import annotations

import argparse
import math
from pathlib import Path
from typing import Dict

import timm
import torch
from rich.console import Console
from rich.table import Table
from torch import nn
from torch.optim import AdamW
from torch.optim.lr_scheduler import CosineAnnealingLR
from torch.utils.tensorboard import SummaryWriter

from .datasets import DATASETS, DatasetConfig, create_dataloaders
from .utils import save_json

console = Console()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Train plant disease classifiers.")
    parser.add_argument("--dataset", choices=DATASETS.keys(), required=True, help="Dataset key (indoor/outdoor)")
    parser.add_argument("--data-root", type=Path, default=Path("."), help="Root directory containing dataset folders")
    parser.add_argument("--epochs", type=int, default=12)
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--num-workers", type=int, default=4)
    parser.add_argument("--lr", type=float, default=3e-4)
    parser.add_argument("--weight-decay", type=float, default=1e-4)
    parser.add_argument("--model-name", type=str, default="efficientnet_b0", help="Any timm model name")
    parser.add_argument("--img-size", type=int, default=384)
    parser.add_argument("--freeze-backbone", action="store_true", help="Freeze backbone for first 2 epochs")
    parser.add_argument("--resume", type=Path, help="Resume from checkpoint (.pth)")
    parser.add_argument("--export", type=Path, help="Export best weights to this path (.pt)")
    parser.add_argument("--device", type=str, default="cuda" if torch.cuda.is_available() else "cpu")
    return parser.parse_args()


def prepare_dataset(cfg: DatasetConfig, root: Path) -> DatasetConfig:
    cfg = DatasetConfig(
        name=cfg.name,
        train_dir=root / cfg.train_dir,
        val_dir=root / cfg.val_dir,
        test_dir=cfg.test_dir and root / cfg.test_dir,
        img_size=cfg.img_size,
        mean=cfg.mean,
        std=cfg.std,
    )
    return cfg


def build_model(model_name: str, num_classes: int) -> nn.Module:
    model = timm.create_model(model_name, pretrained=True, num_classes=num_classes)
    return model


def accuracy(output: torch.Tensor, target: torch.Tensor) -> float:
    preds = torch.argmax(output, dim=1)
    correct = (preds == target).sum().item()
    return correct / target.size(0)


def train_one_epoch(
    model: nn.Module,
    loaders: Dict[str, torch.utils.data.DataLoader],
    optimizer: torch.optim.Optimizer,
    criterion: nn.Module,
    device: torch.device,
    epoch: int,
    writer: SummaryWriter,
) -> float:
    model.train()
    running_loss = 0.0
    running_acc = 0.0
    total = 0

    for step, (images, labels) in enumerate(loaders["train"], start=1):
        images, labels = images.to(device), labels.to(device)
        optimizer.zero_grad()
        outputs = model(images)
        loss = criterion(outputs, labels)
        loss.backward()
        optimizer.step()

        bs = labels.size(0)
        total += bs
        running_loss += loss.item() * bs
        running_acc += accuracy(outputs, labels) * bs

    epoch_loss = running_loss / total
    epoch_acc = running_acc / total
    writer.add_scalar("train/loss", epoch_loss, epoch)
    writer.add_scalar("train/acc", epoch_acc, epoch)
    return epoch_loss


def evaluate(
    model: nn.Module,
    loaders: Dict[str, torch.utils.data.DataLoader],
    criterion: nn.Module,
    device: torch.device,
    epoch: int,
    writer: SummaryWriter,
) -> float:
    model.eval()
    running_loss = 0.0
    running_acc = 0.0
    total = 0

    with torch.no_grad():
        for images, labels in loaders["val"]:
            images, labels = images.to(device), labels.to(device)
            outputs = model(images)
            loss = criterion(outputs, labels)

            bs = labels.size(0)
            total += bs
            running_loss += loss.item() * bs
            running_acc += accuracy(outputs, labels) * bs

    val_loss = running_loss / total
    val_acc = running_acc / total
    writer.add_scalar("val/loss", val_loss, epoch)
    writer.add_scalar("val/acc", val_acc, epoch)
    return val_acc


def main() -> None:
    args = parse_args()
    device = torch.device(args.device)
    cfg = prepare_dataset(DATASETS[args.dataset], args.data_root)
    cfg = DatasetConfig(**{**cfg.__dict__, "img_size": args.img_size})

    loaders = create_dataloaders(
        cfg,
        batch_size=args.batch_size,
        num_workers=args.num_workers,
        use_weighted_sampler=True,
    )
    num_classes = len(cfg.class_names)

    model = build_model(args.model_name, num_classes=num_classes)
    model.to(device)

    backbone_frozen = False
    if args.freeze_backbone:
        for name, param in model.named_parameters():
            if "classifier" not in name and "fc" not in name and "head" not in name:
                param.requires_grad = False
        backbone_frozen = True

    criterion = nn.CrossEntropyLoss()
    optimizer = AdamW(model.parameters(), lr=args.lr, weight_decay=args.weight_decay)
    scheduler = CosineAnnealingLR(optimizer, T_max=args.epochs)

    run_dir = Path(f"ml/outputs/{cfg.name}")
    ckpt_dir = run_dir / "checkpoints"
    log_dir = run_dir / "logs"
    ckpt_dir.mkdir(parents=True, exist_ok=True)
    log_dir.mkdir(parents=True, exist_ok=True)
    writer = SummaryWriter(log_dir=str(log_dir))

    start_epoch = 1
    best_acc = 0.0
    best_path = ckpt_dir / "best.pth"

    if args.resume:
        checkpoint = torch.load(args.resume, map_location=device, weights_only=False)
        model.load_state_dict(checkpoint["model"])
        optimizer.load_state_dict(checkpoint["optimizer"])
        scheduler.load_state_dict(checkpoint["scheduler"])
        start_epoch = checkpoint["epoch"] + 1
        best_acc = checkpoint["best_acc"]
        console.print(f"[yellow]Resumed from {args.resume} (epoch {checkpoint['epoch']})[/yellow]")

    metrics_summary = {}

    for epoch in range(start_epoch, args.epochs + 1):
        console.rule(f"Epoch {epoch}/{args.epochs}")
        if backbone_frozen and epoch >= 3:
            console.print("[cyan]Unfreezing backbone layers[/cyan]")
            for param in model.parameters():
                param.requires_grad = True
            backbone_frozen = False
        train_loss = train_one_epoch(model, loaders, optimizer, criterion, device, epoch, writer)
        val_acc = evaluate(model, loaders, criterion, device, epoch, writer)
        scheduler.step()

        console.print(f"Train loss: {train_loss:.4f} | Val acc: {val_acc:.4f}")
        metrics_summary[epoch] = {"train_loss": train_loss, "val_acc": val_acc}

        state = {
            "epoch": epoch,
            "model": model.state_dict(),
            "optimizer": optimizer.state_dict(),
            "scheduler": scheduler.state_dict(),
            "best_acc": best_acc,
            "config": vars(args),
        }
        torch.save(state, ckpt_dir / f"epoch_{epoch:03d}.pth")

        if val_acc > best_acc:
            best_acc = val_acc
            torch.save(state, best_path)
            console.print(f"[green]New best model saved to {best_path} (acc={best_acc:.4f})[/green]")

    writer.close()
    save_json({"best_acc": best_acc, "epochs": metrics_summary}, run_dir / "metrics.json")

    if args.export:
        console.print(f"[cyan]Exporting best checkpoint to {args.export}[/cyan]")
        best_state = torch.load(best_path, map_location=device, weights_only=False)
        model.load_state_dict(best_state["model"])
        model.eval()
        args.export.parent.mkdir(parents=True, exist_ok=True)
        torch.save(
            {
                "model_name": args.model_name,
                "img_size": cfg.img_size,
                "state_dict": model.state_dict(),
                "class_names": cfg.class_names,
                "mean": cfg.mean,
                "std": cfg.std,
            },
            args.export,
        )

    table = Table(title="Training summary")
    table.add_column("Epoch", justify="right")
    table.add_column("Train Loss")
    table.add_column("Val Acc")
    for epoch, metrics in metrics_summary.items():
        table.add_row(str(epoch), f"{metrics['train_loss']:.4f}", f"{metrics['val_acc']:.4f}")
    console.print(table)
    console.print(f"[bold green]Best validation accuracy: {best_acc:.4f}[/bold green]")


if __name__ == "__main__":
    main()

