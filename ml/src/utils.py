import json
from pathlib import Path
from typing import Iterable, List


def save_json(data, path: Path, *, indent: int = 2) -> None:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        json.dump(data, f, indent=indent, ensure_ascii=False)


def load_class_names(path: Path) -> List[str]:
    path = Path(path)
    with path.open("r", encoding="utf-8") as f:
        data = json.load(f)
    if isinstance(data, dict) and "classes" in data:
        return data["classes"]
    if isinstance(data, list):
        return data
    raise ValueError(f"Unsupported class map format in {path}")


def iter_class_dirs(root: Path) -> Iterable[str]:
    root = Path(root)
    return sorted([p.name for p in root.iterdir() if p.is_dir()])

