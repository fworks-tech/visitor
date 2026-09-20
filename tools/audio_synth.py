#!/usr/bin/env python3
"""DEEPTALES audio synthesis kit (M3) — zero-credit, license-clean audio.

Synthesizes the silence-first analog-horror cue list from a game's
AUDIO_DIRECTION.md as OGG files: ambient loops, the signature knock set,
UI clicks, glitch bursts, and minimal menu/ending music. Everything is
generated mathematically — no third-party samples, no attribution needed
(record in ATTRIBUTIONS.md as in-house / none).

Usage: python3 audio_synth.py [--out assets/audio] [--cue NAME ...]
"""
import argparse
import math
import random
import shutil
import struct
import subprocess
import wave
from pathlib import Path

SR = 22050
RNG = random.Random(1847)  # deterministic builds


# ---------------------------------------------------------------- primitives

def _buf(seconds: float) -> list[float]:
    return [0.0] * int(SR * seconds)


def _add(buf, samples, at: float = 0.0, gain: float = 1.0):
    i0 = int(at * SR)
    for i, s in enumerate(samples):
        j = i0 + i
        if j < len(buf):
            buf[j] += s * gain


def _sine(seconds: float, freq: float, gain: float = 1.0, glide: float = 0.0) -> list[float]:
    out, phase = [], 0.0
    n = int(SR * seconds)
    for i in range(n):
        f = freq + glide * (i / n)
        phase += 2 * math.pi * f / SR
        out.append(gain * math.sin(phase))
    return out


def _noise(seconds: float, gain: float = 1.0, lp: float = 0.0) -> list[float]:
    out, v = [], 0.0
    for _ in range(int(SR * seconds)):
        w = (RNG.random() * 2 - 1) * gain
        if lp:  # one-pole lowpass
            v += lp * (w - v)
            out.append(v)
        else:
            out.append(w)
    return out


def _decay(samples: list[float], tau: float = 0.08) -> list[float]:
    return [s * math.exp(-i / (tau * SR)) for i, s in enumerate(samples)]


def _env(samples: list[float], attack: float = 0.005, release: float = 0.02) -> list[float]:
    n, na, nr = len(samples), int(attack * SR), int(release * SR)
    out = []
    for i, s in enumerate(samples):
        g = min(1.0, i / max(1, na)) * min(1.0, (n - i) / max(1, nr))
        out.append(s * g)
    return out


def _loopify(buf: list[float], fade: float = 0.5) -> list[float]:
    """Crossfade tail into head so the loop point is seamless."""
    n = int(fade * SR)
    if len(buf) <= n * 2:
        return buf
    head, tail = buf[:n], buf[-n:]
    for i in range(n):
        t = i / n
        buf[i] = head[i] * (1 - t) + tail[i] * t
    return buf[:-n]


def _gain(buf, target: float = 0.85):
    peak = max(1e-9, max(abs(s) for s in buf))
    return [s * target / peak for s in buf]


# ---------------------------------------------------------------- cue builders

def knock_single(freq: float = 190.0, dur: float = 0.12, gain: float = 1.0) -> list[float]:
    """Wood-on-wood: noise transient + resonant body."""
    body = _decay(_sine(dur, freq, 0.9), tau=0.035)
    body2 = _decay(_sine(dur, freq * 2.7, 0.35), tau=0.02)
    tr = _env(_noise(0.012, 0.7), 0.0005, 0.005)
    out = [a + b + (tr[i] if i < len(tr) else 0.0) for i, (a, b) in enumerate(zip(body, body2))]
    return [s * gain for s in out]


def cue_knock(pattern: list[float], freq: float = 190.0, gain: float = 1.0) -> list[float]:
    total = pattern[-1] + 0.25
    buf = _buf(total)
    for t in pattern:
        _add(buf, knock_single(freq, gain=gain), at=t)
    return _gain(buf, 0.8 * gain + 0.2)


def cue_ui_click() -> list[float]:
    buf = _buf(0.09)
    _add(buf, _env(_noise(0.006, 0.8), 0.0002, 0.002))
    _add(buf, _decay(_sine(0.05, 1300.0, 0.5), tau=0.012), at=0.004)
    return _gain(buf, 0.5)


def cue_ui_hover() -> list[float]:
    buf = _buf(0.06)
    _add(buf, _env(_sine(0.05, 60.0, 0.25) + _noise(0.05, 0.04, lp=0.2), 0.005, 0.01))
    return _gain(buf, 0.25)


def cue_reveal_sign() -> list[float]:
    buf = _buf(0.45)
    _add(buf, _env(_sine(0.12, 880.0, 0.6), 0.004, 0.03))
    _add(buf, _env(_sine(0.22, 1318.0, 0.5), 0.004, 0.05), at=0.14)
    return _gain(buf, 0.45)


def cue_deadbolt() -> list[float]:
    buf = _buf(0.6)
    for t, f in [(0.0, 300.0), (0.18, 380.0)]:
        _add(buf, _env(_noise(0.01, 0.9, lp=0.6), 0.0003, 0.003), at=t)
        _add(buf, _decay(_sine(0.15, f, 0.7), tau=0.03), at=t)
        _add(buf, _decay(_sine(0.12, f * 1.5, 0.3), tau=0.02), at=t)
    return _gain(buf, 0.65)


def cue_unlock_creak() -> list[float]:
    buf = _buf(0.9)
    _add(buf, _env(_noise(0.008, 0.7), 0.0003, 0.003))  # clack
    creak = _decay(_sine(0.7, 210.0, 0.5, glide=-120.0), tau=0.25)
    creak = [s + RNG.random() * 0.06 * math.sin(2 * math.pi * 47 * i / SR) for i, s in enumerate(creak)]
    _add(buf, _env(creak, 0.02, 0.15), at=0.08)
    return _gain(buf, 0.6)


def cue_gunshot() -> list[float]:
    buf = _buf(0.8)
    _add(buf, _env(_noise(0.03, 1.0), 0.0002, 0.02))
    _add(buf, _decay(_sine(0.4, 60.0, 0.9), tau=0.09))
    _add(buf, _decay(_noise(0.3, 0.15, lp=0.05), tau=0.1), at=0.02)
    return _gain(buf, 0.95)  # loud, no reverb — silence after


def cue_birds() -> list[float]:
    buf = _buf(2.0)
    for t, f in [(0.1, 3200.0), (0.35, 2800.0), (0.9, 3400.0), (1.4, 3000.0)]:
        chirp = _env(_sine(0.14, f, 0.5, glide=900.0), 0.01, 0.02)
        chirp = [s * (1 + 0.6 * math.sin(2 * math.pi * 28 * i / SR)) for i, s in enumerate(chirp)]
        _add(buf, chirp, at=t, gain=0.5)
    return _gain(buf, 0.4)


def cue_glitch(seconds: float, harsh: int = 1) -> list[float]:
    buf = _buf(seconds)
    t = 0.0
    while t < seconds - 0.05:
        seg = RNG.uniform(0.01, 0.06)
        kind = RNG.random()
        if kind < 0.4:
            _add(buf, _env(_noise(seg, 0.9), 0.001, 0.003), at=t, gain=0.5 * harsh)
        elif kind < 0.7:
            _add(buf, _env(_sine(seg, RNG.uniform(120, 1800), 0.6), 0.001, 0.002), at=t, gain=0.5)
        else:  # dropout — leave silence
            pass
        t += seg + RNG.uniform(0.005, 0.05)
    return _gain(buf, 0.5 * harsh)


def cue_drawer_slide() -> list[float]:
    """Wooden drawer: short runner swish, soft wood stop."""
    buf = _buf(0.55)
    _add(buf, _env(_noise(0.3, 0.35, lp=0.3), 0.04, 0.08), at=0.02, gain=0.7)
    _add(buf, knock_single(260.0, gain=0.6), at=0.36)
    return _gain(buf, 0.55)


def cue_water_tap() -> list[float]:
    """Looped trickle: low-passed hiss with irregular little gulps."""
    buf = _noise(3.0, 0.16, lp=0.3)
    for t in [0.2, 0.55, 1.05, 1.4, 1.6, 2.2, 2.55, 2.75]:
        drip = _decay(_sine(0.06, RNG.uniform(700, 1100), 0.5), tau=0.015)
        _add(buf, _env(drip, 0.001, 0.01), at=t, gain=0.5)
    return _loopify(_gain(buf, 0.5), 0.4)


def cue_power_down() -> list[float]:
    buf = _buf(1.4)
    _add(buf, _env(_sine(1.2, 220.0, 0.8, glide=-190.0), 0.005, 0.1))
    _add(buf, _env(_noise(1.2, 0.1, lp=0.3), 0.005, 0.2), gain=0.5)
    return _gain(buf, 0.6)


def cue_heartbeat(bpm_start: float = 72.0, bpm_end: float = 30.0, seconds: float = 14.0) -> list[float]:
    buf = _buf(seconds)
    t = 0.0
    while t < seconds - 1.0:
        for off in (0.0, 0.22):  # lub-dub
            thump = _decay(_sine(0.18, 55.0, 1.0), tau=0.05)
            _add(buf, thump, at=t + off, gain=0.8)
        frac = t / seconds
        bpm = bpm_start + (bpm_end - bpm_start) * frac
        t += 60.0 / bpm
    return _gain(buf, 0.7)


def _pad(freqs: list[float], seconds: float, detune: float = 0.15, tau: float = None) -> list[float]:
    """Soft evolving pad — overlapping decaying sines with slow detune drift."""
    buf = _buf(seconds)
    for i in range(int(seconds / 2.5)):
        for f in freqs:
            _add(buf, _decay(_sine(2.8, f + RNG.uniform(-detune, detune), 0.35),
                             tau=tau or (2.8 / 3)), at=i * 2.5, gain=0.4)
    return buf


def _note(freq: float, dur: float = 1.6, gain: float = 0.5) -> list[float]:
    """Sparse 'piano-ish' FM note with long decay."""
    carrier = _decay(_sine(dur, freq, gain), tau=dur / 4)
    mod = _decay(_sine(dur, freq * 2.0, gain * 0.3), tau=dur / 6)
    return [a + b for a, b in zip(carrier, mod)]


def cue_music_menu() -> list[float]:
    buf = _buf(20.0)
    _add(buf, _pad([55.0, 110.0], 20.0), gain=0.35)  # hum bed
    for t, f in [(0.5, 220.0), (4.2, 164.8), (8.0, 220.0), (12.5, 130.8), (16.0, 174.6)]:
        _add(buf, _note(f, 3.5, 0.5), at=t)
    return _gain(_loopify(buf), 0.55)


def cue_room_tone() -> list[float]:
    buf = _buf(30.0)
    _add(buf, _noise(30.0, 0.12, lp=0.02))
    _add(buf, _sine(30.0, 120.0, 0.05))
    for _ in range(3):  # faint creaks
        _add(buf, _env(_decay(_sine(0.5, RNG.uniform(150, 260), 0.3), tau=0.15), 0.05, 0.1),
            at=RNG.uniform(3, 27), gain=0.25)
    return _gain(_loopify(buf), 0.3)


def cue_crt_hum() -> list[float]:
    buf = _buf(30.0)
    _add(buf, _sine(30.0, 60.0, 0.6))
    _add(buf, _sine(30.0, 120.0, 0.22))
    _add(buf, _sine(30.0, 180.0, 0.10))
    _add(buf, _noise(30.0, 0.05, lp=0.25))
    return _gain(_loopify(buf), 0.4)


def cue_night_drone() -> list[float]:
    buf = _buf(30.0)
    _add(buf, _sine(30.0, 40.0, 0.7))
    _add(buf, _sine(30.0, 40.7, 0.4))
    _add(buf, _sine(30.0, 81.5, 0.12))
    for i in range(len(buf)):  # slow breathing LFO
        buf[i] *= 0.85 + 0.15 * math.sin(2 * math.pi * 0.02 * i / SR)
    return _gain(_loopify(buf), 0.5)


def cue_distant_city() -> list[float]:
    buf = _buf(30.0)
    _add(buf, _noise(30.0, 0.10, lp=0.015))
    for _ in range(2):  # distant siren sweeps
        t = RNG.uniform(5, 20)
        sweep = _env(_sine(4.0, 700.0, 0.1, glide=250.0), 0.8, 1.0)
        _add(buf, sweep, at=t, gain=0.10)
    for _ in range(3):  # far-off wind gusts
        _add(buf, _env(_noise(3.5, 0.15, lp=0.03), 1.0, 1.0), at=RNG.uniform(2, 25), gain=0.2)
    return _gain(_loopify(buf), 0.25)


# ---------------------------------------------------------------- ending cues

def cue_end_gatekeeper() -> list[float]:
    buf = _buf(14.0)
    _add(buf, _pad([220.0, 277.2, 329.6, 440.0], 14.0, detune=0.05), gain=0.5)
    return _gain(_loopify(buf), 0.5)


def cue_end_pariah() -> list[float]:
    buf = _buf(12.0)
    _add(buf, _sine(12.0, 110.0, 0.5))
    _add(buf, _sine(12.0, 116.5, 0.5))  # dissonant beating
    _add(buf, _sine(12.0, 233.1, 0.2))
    return _gain(buf, 0.45)


def cue_end_executioner() -> list[float]:
    buf = _buf(12.0)
    for i in range(int(12.0 / 0.9)):  # metal-on-metal grind pulses
        _add(buf, _env(_noise(0.5, 0.6, lp=0.5), 0.02, 0.1), at=i * 0.9, gain=0.5)
        _add(buf, _decay(_sine(0.4, RNG.uniform(140, 220), 0.4), tau=0.08), at=i * 0.9 + 0.05)
    return _gain(_loopify(buf), 0.55)


def cue_end_hermit() -> list[float]:
    buf = _buf(16.0)
    t, interval = 0.0, 1.4
    while t < 15.5:
        _add(buf, _note(220.0, 2.5, 0.5), at=t)
        interval *= 1.25  # repeating, slowing, stopping
        t += interval
    return _gain(buf, 0.5)


def cue_end_cure() -> list[float]:
    buf = _buf(14.0)
    _add(buf, _pad([130.8, 164.8, 196.0], 14.0, detune=0.06), gain=0.45)
    for t, f in [(2.0, 523.3), (6.0, 659.3), (10.0, 523.3)]:
        _add(buf, _note(f, 2.0, 0.25), at=t)
    _add(buf, _env(_noise(2.0, 0.05, lp=0.4), 1.0, 1.0), at=12.0)  # fades to static
    return _gain(_loopify(buf), 0.5)


def cue_end_infected() -> list[float]:
    buf = cue_heartbeat(bpm_start=60.0, bpm_end=18.0, seconds=12.0)
    _add(buf, _sine(2.5, 1000.0, 0.12), at=12.0)  # flatline
    return _gain(buf, 0.6)


def cue_end_exile() -> list[float]:
    buf = _buf(12.0)
    _add(buf, _noise(12.0, 0.18, lp=0.08))  # indistinct murmur bed
    for i in range(20):  # arguing voices — filtered warbles
        t = RNG.uniform(0.5, 9.0)
        _add(buf, _env(_sine(RNG.uniform(0.15, 0.4), RNG.uniform(110, 180), 0.5,
                             glide=RNG.uniform(-40, 40)), 0.02, 0.05), at=t, gain=0.2)
    _add(buf, _decay(_sine(0.4, 90.0, 1.0), tau=0.1), at=10.2)  # door slam
    _add(buf, _env(_noise(0.05, 0.8), 0.0005, 0.01), at=10.2)
    return _gain(buf, 0.5)


# ---------------------------------------------------------------- cue table

CUES = {
    # ambient (looped)
    "ambient_room_tone":      (cue_room_tone, True),
    "ambient_crt_hum":        (cue_crt_hum, True),
    "ambient_night_drone":    (cue_night_drone, True),
    "ambient_distant_city":   (cue_distant_city, True),
    # knocks (the signature sounds)
    "sfx_knock_1": (lambda: cue_knock([0.0, 0.35, 0.70], freq=190.0), False),          # standard: three firm
    "sfx_knock_2": (lambda: cue_knock([0.0, 0.11, 0.22, 0.33, 0.42, 0.52], freq=205.0), False),  # desperate: rapid
    "sfx_knock_3": (lambda: cue_knock([0.0, 0.80], freq=175.0), False),                 # calm: two slow
    "sfx_knock_4": (lambda: cue_knock([0.0, 0.30, 0.60], freq=320.0, gain=0.35), False),# child: small, quiet
    "sfx_knock_5": (lambda: cue_knock([0.0, 0.15, 0.19, 0.35, 0.42, 0.55, 0.61, 0.78, 0.82, 0.95], freq=185.0), False),  # group chaos
    "sfx_knock_6": (lambda: cue_knock([0.0, 0.35, 0.70], freq=196.0), False),            # return: recognizable echo of 1
    # UI
    "sfx_ui_click":             (cue_ui_click, False),
    "sfx_ui_hover":             (cue_ui_hover, False),
    "sfx_reveal_sign":          (cue_reveal_sign, False),
    "sfx_decision_let_in":      (cue_unlock_creak, False),
    "sfx_decision_turn_away":   (cue_deadbolt, False),
    "sfx_decision_eliminate":   (cue_gunshot, False),
    "sfx_day_transition":       (cue_birds, False),
    # glitch
    "sfx_glitch_1": (lambda: cue_glitch(0.5, harsh=1), False),
    "sfx_glitch_2": (lambda: cue_glitch(1.0, harsh=1), False),
    "sfx_glitch_3": (lambda: cue_glitch(2.0, harsh=2), False),
    "sfx_power_down": (cue_power_down, False),
    # house realism (kitchen)
    "sfx_drawer_slide": (cue_drawer_slide, False),
    "sfx_water_tap":    (cue_water_tap, True),
    # music (menu + endings, used sparingly)
    "music_menu": (cue_music_menu, True),
    "music_ending_gatekeeper":  (cue_end_gatekeeper, True),
    "music_ending_pariah":      (cue_end_pariah, True),
    "music_ending_executioner": (cue_end_executioner, True),
    "music_ending_hermit":     (cue_end_hermit, True),
    "music_ending_cure":       (cue_end_cure, True),
    "music_ending_infected":   (cue_end_infected, False),
    "music_ending_exile":      (cue_end_exile, False),
}


def write_ogg(samples: list[float], out: Path, loop: bool):
    tmp = out.with_suffix(".wav")
    pcm = struct.pack(f"<{len(samples)}h",
                      *[max(-32767, min(32767, int(s * 32767))) for s in samples])
    with wave.open(str(tmp), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm)
    if shutil.which("ffmpeg") is None:
        # No ffmpeg here: keep the WAV — Godot imports it natively and
        # AudioManager falls back to .wav when the .ogg cue is absent.
        print(f"  (no ffmpeg — kept {tmp.name}, Godot WAV import)")
        return
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(tmp),
                    "-c:a", "libvorbis", "-qscale:a", "4", str(out)], check=True)
    tmp.unlink()
    if loop:  # Godot reads the loop flag from metadata comment
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(out),
                        "-c", "copy", "-metadata",
                        "LOOP_START=0", str(out.with_name(out.stem + "_tmp.ogg"))], check=True)
        out.with_name(out.stem + "_tmp.ogg").replace(out)


def main() -> None:
    ap = argparse.ArgumentParser(description="DEEPTALES audio synthesis kit (M3)")
    ap.add_argument("--out", default="assets/audio", help="output directory")
    ap.add_argument("--cue", action="append", help="synthesize only these cues (repeatable)")
    args = ap.parse_args()

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    names = args.cue or list(CUES)
    for name in names:
        builder, loop = CUES[name]
        print(f"  synth {name} ({'loop' if loop else 'one-shot'})...", flush=True)
        write_ogg(builder(), out / f"{name}.ogg", loop)
    print(f"✓ {len(names)} cue(s) -> {out}/ (OGG Vorbis, {SR} Hz mono)")


if __name__ == "__main__":
    main()
