from pathlib import Path
import wave, struct, math, hashlib
root = Path(__file__).resolve().parents[2] / 'Myaow' / 'Resources' / 'Sounds'
expected = {'classic','electric','cosmic','melodic','claw','lazy','kiss','giggle','party','question','sleepy','echo','mentada','admiration'}
hashes = set()
for name in sorted(expected):
    with wave.open(str(root / f'myaow-{name}.wav')) as audio:
        assert audio.getnchannels() == 1 and audio.getsampwidth() == 2
        assert audio.getframerate() == 44100
        duration = audio.getnframes() / audio.getframerate()
        assert .4 <= duration < 2, (name, duration)
        data = audio.readframes(audio.getnframes())
    samples = struct.unpack('<'+'h'*(len(data)//2), data)
    peak = max(map(abs,samples))/32768
    rms = math.sqrt(sum((x/32768)**2 for x in samples)/len(samples))
    dc = abs(sum(samples)/len(samples)/32768)
    assert .3 < peak < .68 and .13 < rms < .20, (name,peak,rms)
    assert dc < .003, (name,dc)
    assert abs(samples[0]) < 2 and abs(samples[-1]) < 2
    assert max(abs(b-a) for a,b in zip(samples,samples[1:])) < 10000, name
    hashes.add(hashlib.sha256(data).digest())
assert len(hashes) == len(expected)
print(f'{len(expected)} distinct PCM notification assets: duration, headroom, loudness, DC and fades passed.')
