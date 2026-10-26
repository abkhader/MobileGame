#!/usr/bin/env python3
"""Generates Echo's sound assets into app/assets/audio (standard library only).

Output is deterministic: running it twice yields byte-identical files.
"""
import math
import os
import random
import struct
import wave

RATE = 22050
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   '..', '..', 'app', 'assets', 'audio')


def seconds(n):
    return int(round(n * RATE))


def sine(freq, i, phase=0.0):
    return math.sin(2 * math.pi * freq * i / RATE + phase)


def fade(samples, fade_in=0.004, fade_out=0.01):
    """Applies short linear fades so nothing clicks."""
    n = len(samples)
    a = min(seconds(fade_in), n // 2)
    b = min(seconds(fade_out), n // 2)
    for i in range(a):
        samples[i] *= i / a
    for i in range(b):
        samples[n - 1 - i] *= i / b
    return samples


def tone(freq, dur, decay=None, amp=0.6):
    n = seconds(dur)
    return [
        amp * sine(freq, i) * (math.exp(-decay * i / RATE) if decay else 1.0)
        for i in range(n)
    ]


def move():
    return fade(tone(880, 0.060, decay=60, amp=0.5), 0.002, 0.01)


def plate():
    return fade(tone(220, 0.120, decay=25, amp=0.8), 0.003, 0.02)


def door():
    n = seconds(0.180)
    out = []
    phase = 0.0
    for i in range(n):
        f = 300 + 300 * i / n
        phase += 2 * math.pi * f / RATE
        out.append(0.5 * math.sin(phase) * (1 - 0.3 * i / n))
    return fade(out, 0.005, 0.03)


def run_end():
    first = fade(tone(660, 0.175, decay=8, amp=0.5), 0.004, 0.03)
    second = fade(tone(440, 0.175, decay=8, amp=0.5), 0.004, 0.04)
    return first + second


def win():
    out = []
    for f in (523, 659, 784):
        out += fade(tone(f, 0.200, decay=3, amp=0.45), 0.004, 0.03)
    return out


def bump():
    # A soft, short "push" tick: low thump with a quiet overtone.
    n = seconds(0.055)
    out = [
        (0.55 * sine(150, i) + 0.2 * sine(300, i))
        * math.exp(-55 * i / RATE)
        for i in range(n)
    ]
    return fade(out, 0.002, 0.012)


def spark():
    # A bright, short chime: two quick rising bell notes (G6 then D7) with
    # a soft octave shimmer, ringing out fast.
    out = []
    for start, freq in ((0.0, 1568.0), (0.045, 2349.0)):
        begin = seconds(start)
        n = seconds(0.22)
        while len(out) < begin + n:
            out.append(0.0)
        for i in range(n):
            env = math.exp(-22 * i / RATE)
            out[begin + i] += 0.28 * env * (
                sine(freq, i) + 0.35 * sine(freq * 2, i)
                + 0.12 * sine(freq * 3, i))
    return fade(out, 0.002, 0.03)


def rewind():
    # A rising 0.6 s sweep, 300 -> 900 Hz. The mean frequency (600 Hz) over
    # 0.6 s is a whole number of cycles, and the swell starts and ends at the
    # same level, so the loop is seamless.
    n = seconds(0.6)
    t_total = n / RATE
    f0, f1 = 300.0, 900.0
    out = []
    for i in range(n):
        t = i / RATE
        phase = 2 * math.pi * (f0 * t + (f1 - f0) * t * t / (2 * t_total))
        swell = 0.7 + 0.3 * math.sin(2 * math.pi * t / t_total)
        out.append(0.3 * swell * (math.sin(phase) + 0.3 * math.sin(2 * phase)))
    return out


def ambient():
    n = seconds(16)
    rng = random.Random(7)
    parts = []
    # (frequency Hz, swell cycles in 16 s); all integer cycles => seamless.
    for freq, swell in ((110, 1), (165, 2), (220, 3)):
        parts.append((freq, swell, rng.uniform(0, 2 * math.pi)))
    out = []
    for i in range(n):
        t = i / RATE
        s = 0.0
        for k, (freq, swell, ph) in enumerate(parts):
            lfo = 0.65 + 0.35 * math.sin(2 * math.pi * swell * t / 16 + ph)
            s += (1.0 / (k + 1)) * lfo * math.sin(2 * math.pi * freq * t)
        out.append(s)
    peak = max(abs(x) for x in out)
    gain = (10 ** (-12 / 20)) / peak  # peak at -12 dBFS
    return [x * gain for x in out]


def write(name, samples):
    path = os.path.join(OUT, name + '.wav')
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b''.join(
            struct.pack('<h', max(-32767, min(32767, int(round(x * 32767)))))
            for x in samples))


def main():
    random.seed(7)
    os.makedirs(OUT, exist_ok=True)
    write('move', move())
    write('plate', plate())
    write('door', door())
    write('run_end', run_end())
    write('win', win())
    write('bump', bump())
    write('spark', spark())
    write('rewind', rewind())
    write('ambient', ambient())


if __name__ == '__main__':
    main()
