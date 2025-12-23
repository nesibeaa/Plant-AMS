"""
Overfitting önleme için notebook'a eklenecek değişiklikler
Bu kodları notebook'un run_experiment fonksiyonuna ekle
"""

# ============================================
# OVERFITTING ÖNLEME DEĞİŞİKLİKLERİ
# ============================================

# 1. MODEL MİMARİSİ - Dropout artırıldı
# MultiOutputModel'de dropout=0.3 → dropout=0.5 yap
# SingleOutputModel'de de aynı şekilde

# 2. OPTIMIZER - Weight Decay eklendi
# Şu anki kod:
# optimizer_multi = torch.optim.Adam(model_multi.parameters(), lr=learning_rate)

# Yeni kod:
optimizer_multi = torch.optim.Adam(
    model_multi.parameters(), 
    lr=learning_rate,
    weight_decay=1e-4  # L2 Regularization - Overfitting önler
)

# 3. DATA AUGMENTATION - Güçlendirildi
# Şu anki train_transform'a ekle:

train_transform = A.Compose([
    A.RandomResizedCrop(224, 224, scale=(0.7, 1.0)),  # Daha agresif crop
    A.HorizontalFlip(p=0.5),
    A.VerticalFlip(p=0.3),  # Yeni: Dikey flip
    A.RandomRotate90(p=0.3),  # Yeni: 90 derece rotasyon
    A.ShiftScaleRotate(shift_limit=0.1, scale_limit=0.2, rotate_limit=15, p=0.5),  # Yeni
    A.RandomBrightnessContrast(brightness_limit=0.3, contrast_limit=0.3, p=0.5),  # Güçlendirildi
    A.ColorJitter(brightness=0.3, contrast=0.3, saturation=0.3, hue=0.1, p=0.5),  # Yeni
    A.GaussNoise(var_limit=(10.0, 50.0), p=0.3),  # Yeni: Gürültü ekleme
    A.CoarseDropout(max_holes=8, max_height=32, max_width=32, p=0.3),  # Yeni: Random erasing
    A.Normalize(mean=(0.485, 0.456, 0.406), std=(0.229, 0.224, 0.225)),
    ToTensorV2()
])

# 4. EARLY STOPPING - Eklendi
# run_experiment fonksiyonuna ekle:

class EarlyStopping:
    def __init__(self, patience=5, min_delta=0.001):
        self.patience = patience
        self.min_delta = min_delta
        self.counter = 0
        self.best_loss = float('inf')
        
    def __call__(self, val_loss):
        if val_loss < self.best_loss - self.min_delta:
            self.best_loss = val_loss
            self.counter = 0
            return False  # Devam et
        else:
            self.counter += 1
            if self.counter >= self.patience:
                return True  # Dur
            return False  # Devam et

# Training loop'a ekle:
early_stopping = EarlyStopping(patience=5, min_delta=0.001)

for epoch in range(num_epochs):
    # ... training ve validation ...
    
    # Early stopping kontrolü
    if early_stopping(val_loss):
        print(f"\n⏹️  Early stopping at epoch {epoch+1}")
        print(f"   Best validation loss: {early_stopping.best_loss:.4f}")
        break

# 5. LEARNING RATE SCHEDULER - Güçlendirildi
# Şu anki kod:
# scheduler_multi = torch.optim.lr_scheduler.ReduceLROnPlateau(...)

# Yeni kod (daha agresif):
scheduler_multi = torch.optim.lr_scheduler.ReduceLROnPlateau(
    optimizer_multi, 
    mode='min', 
    factor=0.5,  # Learning rate'i yarıya indir
    patience=3,  # 3 epoch beklenmeden azalt
    verbose=True,
    min_lr=1e-6  # Minimum learning rate
)

# ============================================
# ÖZET DEĞİŞİKLİKLER
# ============================================
"""
1. Dropout: 0.3 → 0.5 (Model daha genel öğrenir)
2. Weight Decay: 1e-4 eklendi (Ağırlıklar küçük tutulur)
3. Data Augmentation: Güçlendirildi (Daha fazla çeşitlilik)
4. Early Stopping: Eklendi (Overfitting başlamadan durur)
5. Learning Rate Scheduler: Güçlendirildi (Daha iyi yakınsama)
"""

