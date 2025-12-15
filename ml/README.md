# Plant Health ML Pipeline

This directory contains the assets required to train and serve image-based plant health classifiers for the **indoor** and **outdoor** datasets that ship with the project.

## Directory Structure

```
ml/
├── README.md                # This file
├── requirements-ml.txt      # Python dependencies for training
├── notebooks/               # (optional) Exploratory notebooks
├── src/
│   ├── datasets.py          # Data loading helpers
│   ├── train_classifier.py  # Training entrypoint
│   ├── evaluate.py          # Evaluation utilities
│   └── utils.py             # Shared helpers
└── outputs/
    ├── indoor/
    │   ├── checkpoints/     # Saved indoor model weights
    │   └── logs/            # Training metrics
    └── outdoor/
        ├── checkpoints/
        └── logs/
```

> The `outputs/` directory is Git-ignored. You can safely store large model artifacts there without affecting the repository.

## Datasets

- `indoor/`: Decorative house plants (Aloe, Cactus, Money Plant, Snake Plant, Spider Plant) with multiple disease classes. Split into `train/`, `valid/`, `test/`.
- `outdoor/`: Field crops (Apple, Corn, Grape, Tomato, etc.) from the “New Plant Diseases Dataset (Augmented)” release. Contains `train/` and `valid/` splits plus an additional `test/`.

### Class Index Files

For inference we need the list of class names in a stable order. Use the helper script below to generate JSON files from the folder structure:

```bash
python -m ml.src.datasets --scan ./indoor/train --output backend/models/indoor_classes.json
python -m ml.src.datasets --scan "./outdoor/New Plant Diseases Dataset(Augmented)/New Plant Diseases Dataset(Augmented)/train" --output backend/models/outdoor_classes.json
```

These JSON files are loaded by the FastAPI backend when serving predictions.

## Environment Setup

Create or reuse a virtual environment (e.g. `.venv/`) and install training dependencies:

```bash
python -m pip install -r ml/requirements-ml.txt
```

The file includes `torch`, `torchvision`, `timm`, and logging utilities (`tensorboard`, `rich`).

## Training

Run a baseline training job for the indoor dataset:

```bash
python -m ml.src.train_classifier \
  --data-root ./indoor \
  --dataset indoor \
  --model-name efficientnet_b0 \
  --epochs 10 \
  --batch-size 32
```

For the outdoor dataset:

```bash
python -m ml.src.train_classifier \
  --data-root "./outdoor/New Plant Diseases Dataset(Augmented)/New Plant Diseases Dataset(Augmented)" \
  --dataset outdoor \
  --model-name efficientnet_b2 \
  --epochs 12 \
  --batch-size 48
```

Both commands will save checkpoints into `ml/outputs/<dataset>/checkpoints/` and write TensorBoard logs.

### Transfer Learning Architecture

The training script uses EfficientNet (via `timm`) by default. You can adjust:

- `--model-name`: any model supported by `timm.create_model`
- `--lr`: learning rate (default `3e-4`)
- `--img-size`: resize dimension (default `384`)
- `--freeze-backbone`: freeze all layers except the classifier head for the first phase

## Exporting Models

Once satisfied with validation metrics, export the best checkpoint:

```bash
python -m ml.src.train_classifier \
  --resume ml/outputs/indoor/checkpoints/best.pth \
  --export backend/models/indoor_classifier.pt \
  --dataset indoor
```

Repeat for outdoor data. The exported `.pt` files are consumed by the FastAPI backend.

## Evaluation

To evaluate an exported model on the `test/` split:

```bash
python -m ml.src.evaluate \
  --data-root ./indoor \
  --dataset indoor \
  --weights backend/models/indoor_classifier.pt
```

This prints accuracy, macro F1, and class-wise metrics, and can optionally write a confusion matrix.

---

Need help running a specific experiment? Reach out and we can pair on the training configuration.

