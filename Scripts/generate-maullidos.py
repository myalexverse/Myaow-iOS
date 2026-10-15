"""Original Myaow sound design. Reproducible, PCM16 mono; no downloaded samples.
Integrated phase, band-limited harmonics, gentle envelopes, normalized headroom.
"""
from pathlib import Path
import math, struct, wave
RATE = 44100
DEST = Path(__file__).resolve().parents[1] / 'Myaow' / 'Resources' / 'Sounds'
DEST.mkdir(parents=True, exist_ok=True)
DURATIONS = dict(classic=0.82, electric=0.66, cosmic=1.24, melodic=1.08, claw=0.70, lazy=1.36, kiss=.72, giggle=1.12, party=1.45, question=.94, sleepy=1.60, echo=1.48, mentada=1.72, admiration=1.58)

def render(name, duration):
    samples, phase = [], 0.0
    for i in range(round(RATE * duration)):
        t = i / RATE
        u = t / duration
        # Soft vocal rise and falling vowel; tame upper harmonics for phone speakers.
        pitch = 430 + 225 * math.sin(math.pi * u) - 150 * u
        pulse = 1.0
        if name == 'electric': pitch = 570 + 210 * math.sin(math.pi*u) + 18 * math.sin(2*math.pi*27*t)
        elif name == 'cosmic': pitch = 150 + 20 * math.sin(math.pi*u); pulse = .62 + .38 * math.sin(2*math.pi*24*t)**2
        elif name == 'melodic':
            note = min(2, int(u * 3))
            pitch = [523.25, 659.25, 783.99][note]
            pulse = math.sin(math.pi * ((u*3) % 1))**2
        elif name == 'claw': pitch = 310 + 240 * math.sin(math.pi*u); pulse = .8 + .2*math.sin(2*math.pi*37*t)
        elif name == 'lazy': pitch = 340 + 100*math.sin(math.pi*u)-130*u
        elif name == 'kiss': pitch = 620-310*u; pulse = math.sin(math.pi*u)**2
        elif name == 'giggle': pitch = 510+160*math.sin(2*math.pi*5*t); pulse = .25+.75*math.sin(2*math.pi*3*t)**2
        elif name == 'party': pitch = [523,659,784,1046][min(3,int(u*4))]; pulse = math.sin(math.pi*((u*4)%1))**2
        elif name == 'question': pitch = 350+440*u*u
        elif name == 'sleepy': pitch = 280-120*u; pulse = .7+.3*math.sin(2*math.pi*8*t)**2
        elif name == 'echo': pitch = 600-180*u; pulse = math.exp(-2*u)*(.55+.45*math.cos(2*math.pi*4*t)**2)
        elif name in ('mentada', 'admiration'):
            # Familiar whistle phrasing voiced as a cat: five clipped syllables,
            # or a rising call followed by a long falling answer. Original synthesis.
            notes = ([(.04,.25,830,760),(.31,.43,660,630),(.48,.60,660,640),
                      (.67,.89,740,710),(1.03,1.60,620,410)] if name == 'mentada' else
                     [(.04,.57,550,1170),(.72,1.48,1140,520)])
            pulse = 0.0
            for start, end, first, last in notes:
                if start <= t < end:
                    position = (t-start)/(end-start)
                    pitch = first + (last-first)*position + 8*math.sin(2*math.pi*7*t)
                    attack = min(1,(t-start)/.035)
                    release = min(1,(end-t)/.07)
                    pulse = (.5-.5*math.cos(math.pi*attack))*(.5-.5*math.cos(math.pi*release))
                    break
        phase += 2*math.pi*pitch/RATE
        vowel = .52 + .25*math.sin(math.pi*u)
        sample = math.sin(phase) + vowel*math.sin(2*phase) + .20*math.sin(3*phase) + .08*math.sin(4*phase)
        if name == 'electric': sample += .12*math.sin(phase*6)
        attack = min(1, t/.035)
        release = min(1, (duration-t)/.14)
        env = (.5-.5*math.cos(math.pi*attack))*(.5-.5*math.cos(math.pi*release))*math.sin(math.pi*u)**.55
        samples.append(sample*env*pulse)
    peak = max(abs(x) for x in samples)
    rms = math.sqrt(sum(x*x for x in samples)/len(samples))
    gain = min(.66/peak, .19/rms)
    return [round(x*gain*32767) for x in samples]

for name, duration in DURATIONS.items():
    values = render(name, duration)
    with wave.open(str(DEST/f'myaow-{name}.wav'), 'wb') as f:
        f.setparams((1,2,RATE,0,'NONE','not compressed'))
        f.writeframes(struct.pack('<'+'h'*len(values),*values))
    assert max(map(abs,values)) < 22000
    assert abs(values[0]) <= 1 and abs(values[-1]) <= 1
    assert duration < 30
    print(name, duration, 'seconds; peak', max(map(abs,values)))
