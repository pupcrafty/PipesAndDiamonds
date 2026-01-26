import time
import json
import logging
import os
import numpy as np
import sounddevice as sd
import aubio
from pythonosc.udp_client import SimpleUDPClient

# ----------------------------
# Load configuration
# ----------------------------
CONFIG_PATH = os.path.join(os.path.dirname(__file__), "config.json")
with open(CONFIG_PATH, "r") as f:
    config = json.load(f)

# Set up logging
log_config = config.get("logging", {})
log_level = getattr(logging, log_config.get("level", "INFO").upper())
log_format = log_config.get("format", "%(asctime)s - %(name)s - %(levelname)s - %(message)s")
log_date_format = log_config.get("date_format", "%Y-%m-%d %H:%M:%S")

logging.basicConfig(
    level=log_level,
    format=log_format,
    datefmt=log_date_format
)
logger = logging.getLogger(__name__)

# ----------------------------
# OSC target (Godot will listen here)
# ----------------------------
OSC_HOST = "127.0.0.1"
OSC_PORT = 9000

# ----------------------------
# Audio capture settings
# ----------------------------
SAMPLERATE = 44100
HOP_SIZE = 512          # lower = lower latency, higher = more stable
WIN_SIZE = 1024         # should be >= HOP_SIZE

# ----------------------------
# Tempo smoothing / gating
# ----------------------------
CONF_MIN = 0.25         # below this, BPM updates are ignored
BPM_MIN = 70.0
BPM_MAX = 180.0
BPM_EMA_ALPHA = 0.08    # 0..1 (smaller = smoother)
BPM_RESEND_HZ = 10      # resend BPM/conf as "state" even between beats

# ----------------------------
# Channels
# ----------------------------
INPUT_CHANNELS = 1      # set to 2 if you want stereo capture
DEVICE = None           # set to an integer device index if needed

osc = SimpleUDPClient(OSC_HOST, OSC_PORT)

tempo = aubio.tempo("default", WIN_SIZE, HOP_SIZE, SAMPLERATE)

beat_id = 0
bpm_est = 120.0
conf_est = 0.0
last_state_send = 0.0


def clamp(x, lo, hi):
    return lo if x < lo else hi if x > hi else x


def ema(old, new, alpha):
    return (1.0 - alpha) * old + alpha * new


def send_state(now):
    # "State" messages: safe to resend frequently
    osc.send_message("/clock/bpm", float(bpm_est))
    osc.send_message("/clock/conf", float(conf_est))
    osc.send_message("/clock/beat_id", int(beat_id))
    osc.send_message("/clock/time", float(now))


def audio_callback(indata, frames, time_info, status):
    global beat_id, bpm_est, conf_est, last_state_send

    if status:
        # Non-fatal (buffer underrun, etc.)
        logger.warning(f"Audio status: {status}")

    # Mixdown to mono float32
    if INPUT_CHANNELS > 1:
        samples = np.mean(indata, axis=1).astype(np.float32)
    else:
        samples = indata[:, 0].astype(np.float32)

    # aubio expects a vector of floats
    is_beat = tempo(samples)
    bpm_raw = float(tempo.get_bpm())
    conf_raw = float(tempo.get_confidence())

    # Keep a running confidence estimate (EMA)
    conf_est = ema(conf_est, clamp(conf_raw, 0.0, 1.0), 0.15)

    now = time.time()

    # Update BPM only when plausible and confident
    if BPM_MIN <= bpm_raw <= BPM_MAX and conf_raw >= CONF_MIN:
        old_bpm = bpm_est
        bpm_est = ema(bpm_est, bpm_raw, BPM_EMA_ALPHA)
        if abs(bpm_est - old_bpm) > 0.5:  # Log significant BPM changes
            logger.info(f"BPM updated: {bpm_est:.1f} (raw: {bpm_raw:.1f}, confidence: {conf_raw:.2f})")

    # Beat event
    if is_beat:
        beat_id += 1
        logger.info(f"Beat detected: beat_id={beat_id}, BPM={bpm_est:.1f}, confidence={conf_est:.2f}")
        osc.send_message("/clock/beat", int(beat_id))
        # Optional: send bpm/conf on beat too (helps Godot lock quickly)
        send_state(now)

    # Periodic resend of state (so late joiners sync, and Godot stays updated)
    if now - last_state_send >= (1.0 / BPM_RESEND_HZ):
        last_state_send = now
        send_state(now)


def main():
    logger.info("Starting aubio → OSC bridge")
    logger.info(f"OSC target: {OSC_HOST}:{OSC_PORT}")
    logger.info(f"Audio: {SAMPLERATE} Hz, hop={HOP_SIZE}, win={WIN_SIZE}, channels={INPUT_CHANNELS}")
    logger.info(f"Logging level: {logging.getLevelName(logger.level)}")

    with sd.InputStream(
        device=DEVICE,
        channels=INPUT_CHANNELS,
        samplerate=SAMPLERATE,
        blocksize=HOP_SIZE,
        dtype="float32",
        callback=audio_callback,
    ):
        logger.info("Audio stream started, listening for beats...")
        while True:
            time.sleep(0.25)


if __name__ == "__main__":
    main()