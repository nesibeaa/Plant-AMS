#!/usr/bin/env python3
import time, random, requests
import datetime as dt
import sys

API = "http://127.0.0.1:8000/api/v1/ingest"  # dikkat: doğru endpoint

# ---------- Ayarlar ----------
INTERVAL_SEC = 15.0           # okuma aralığı (sn)
# random-walk parametreleri (taban aralıklar)
RANGE = {
    "temp":     (15.0, 27.0),
    "humidity": (40.0, 85.0),
    "co2":      (380.0, 1250.0),
}
CENTER = {
    "temp": 21.0,
    "humidity": 60.0,
    "co2": 650.0,
}
# her adım gürültüsü
JITTER = {
    "temp":     0.08,
    "humidity": 0.12,
    "co2":      2.0,
}
# spike olasılığı (her tur)
SPIKE_PROB = {
    "temp":     0.015,
    "humidity": 0.015,
    "co2":      0.025,
}
# spike delta aralığı (anlık sapma)
SPIKE_DELTA = {
    "temp":     (-3.5, 4.0),
    "humidity": (-18.0, 20.0),
    "co2":      (-200.0, 300.0),
}
FORCED_INTERVAL = {
    "temp":     (10, 14),   # ~2.5 - 3.5 dk
    "humidity": (10, 14),
    "co2":      (8, 12),
}
# spike süresi (kaç okuma boyunca sürsün)
SPIKE_LEN = {
    "temp":     (2, 3),
    "humidity": (2, 3),
    "co2":      (3, 4),
}
# sensörler
SENSORS = [
    ("temp-1", "temp"),
    ("hum-1",  "humidity"),
    ("co2-1",  "co2"),
]
# --------------------------------

def iso_utc_z():
    """UTC timezone-aware ISO8601 string (Z soneki)."""
    return dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")

class RandomWalk:
    def __init__(self, kind: str, v0: float):
        self.kind = kind
        self.v = v0
        self.spike_left = 0
        self.spike_value = None
        lo, hi = FORCED_INTERVAL[self.kind]
        self.force_countdown = random.randint(lo, hi)

    def step(self) -> float:
        lo, hi = RANGE[self.kind]

        # Aktif spike varsa devam et
        if self.spike_left > 0:
            self.spike_left -= 1
            return self.spike_value

        # Zorunlu spike zamanlaması
        self.force_countdown -= 1
        if self.force_countdown <= 0:
            flo, fhi = FORCED_INTERVAL[self.kind]
            self.force_countdown = random.randint(flo, fhi)
            a, b = SPIKE_DELTA[self.kind]
            spike_target = self.v + random.uniform(a, b)
            self.spike_value = max(lo, min(hi, spike_target))
            self.spike_left = random.randint(*SPIKE_LEN[self.kind])
            return self.spike_value

        # Yeni spike başlat?
        if random.random() < SPIKE_PROB[self.kind]:
            a, b = SPIKE_DELTA[self.kind]
            spike_target = self.v + random.uniform(a, b)
            self.spike_value = max(lo, min(hi, spike_target))
            self.spike_left = random.randint(*SPIKE_LEN[self.kind])
            return self.spike_value

        # Normal random-walk (mean reversion)
        towards_center = (CENTER[self.kind] - self.v) * 0.05
        noise = random.uniform(-JITTER[self.kind], JITTER[self.kind])
        self.v += towards_center + noise
        # sınırla
        self.v = max(lo, min(hi, self.v))
        return self.v

def main():
    # başlangıç değerleri (aralığın orta noktası)
    state = {k: CENTER[k] for k in CENTER}
    walkers = {k: RandomWalk(k, v0) for k, v0 in state.items()}

    print(f"🔥 Simulator → {API}  (interval={INTERVAL_SEC}s)")
    try:
        while True:
            ts = iso_utc_z()

            # her sensör için bir değer üret ve gönder
            line = [dt.datetime.now().strftime("%H:%M:%S")]
            all_ok = True
            for sid, kind in SENSORS:
                val = round(walkers[kind].step(), 2)
                payload = {"sensor_id": sid, "type": kind, "value": val, "ts": ts}
                try:
                    r = requests.post(API, json=payload, timeout=5)
                    ok = (200 <= r.status_code < 300)
                    all_ok = all_ok and ok
                except Exception as e:
                    ok = False
                    all_ok = False
                line.append(f"{kind}={val:>6}")
            print(f"[{line[0]}] {'  '.join(line[1:])}  -> {'OK' if all_ok else 'ERR'}")

            time.sleep(INTERVAL_SEC)
    except KeyboardInterrupt:
        print("\nbye.")

if __name__ == "__main__":
    # komut satırından hız vermek istersen: python simulate.py 2.0
    if len(sys.argv) > 1:
        try:
            INTERVAL_SEC = float(sys.argv[1])
        except Exception:
            pass
    main()
    