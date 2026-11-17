"""Modelo de referencia bit a bit del procesamiento PPG de la FPGA.

Reproduce con enteros y desplazamientos exactamente lo que hacen los módulos
de fpga/rtl (ppg_processor, ppg_filter, pulse_detector y bpm_calc), muestra
por muestra. Sirve para comparar la simulación Verilog contra una referencia
independiente con la misma secuencia de entrada (guía, paso 2.4).

Si se cambia un parámetro aquí, debe cambiarse también en el RTL.
"""

from collections import deque

# Parámetros compartidos con el RTL (ver fpga/README.md).
SAMPLE_HZ = 100
BASE_SHIFT = 5          # Línea base: media exponencial con constante 2^5 muestras (fc ~ 0.5 Hz).
AVG_LOG2 = 3            # Suavizado: promedio móvil de 2^3 = 8 muestras.
ENV_DECAY_SHIFT = 7     # Decaimiento de la envolvente de picos.
MIN_AMP = 20            # Amplitud mínima (cuentas) para aceptar un pulso.
REFRACT = 25            # Periodo refractario: 25 muestras = 250 ms (240 BPM).
MIN_N = 25              # Intervalo mínimo aceptado (240 BPM).
MAX_N = 200             # Intervalo máximo aceptado (30 BPM).
STABLE_BEATS = 4        # Intervalos consistentes antes de declarar BPM válido.
CNT_MAX = 511           # Saturación del contador de muestras (9 bits).
SAT_LEVEL = 0xFF00      # IR >= SAT_LEVEL: saturación.
CONTACT_MIN = 8000      # IR < CONTACT_MIN: sin dedo / sin contacto.

# Bits de signal_quality.
Q_SAT = 1 << 0
Q_CONTACT = 1 << 1
Q_FIFO = 1 << 2
Q_GAP = 1 << 3
Q_LOWAMP = 1 << 4


class PpgFilter:
    """Línea base exponencial + promedio móvil (ppg_filter.v)."""

    def __init__(self):
        self.restart()

    def restart(self):
        self.primed = False
        self.acc = 0
        self.win = deque([0] * (1 << AVG_LOG2))
        self.sum = 0

    def step(self, x):
        if not self.primed:
            self.acc = x << BASE_SHIFT
            self.primed = True
            ac = 0
        else:
            base = self.acc >> BASE_SHIFT
            ac = base - x  # Invertida: el pulso sistólico queda positivo.
            self.acc = self.acc + x - base
        oldest = self.win.popleft()
        self.win.append(ac)
        self.sum = self.sum + ac - oldest
        return self.sum >> AVG_LOG2  # Desplazamiento aritmético, como >>> en Verilog.


class PulseDetector:
    """Umbral adaptativo con histéresis y periodo refractario (pulse_detector.v)."""

    def __init__(self):
        self.restart()

    def restart(self):
        self.env = 0
        self.armed = False
        self.cnt = 0
        self.have_prev = False

    def step(self, s):
        """Devuelve (beat, interval_ok, interval)."""
        thr = self.env >> 1
        cnt_inc = min(self.cnt + 1, CNT_MAX)
        beat = self.armed and s > thr and self.env >= MIN_AMP and cnt_inc >= REFRACT
        interval_ok = beat and self.have_prev
        interval = cnt_inc

        if s > self.env:
            self.env = s
        else:
            self.env = self.env - (self.env >> ENV_DECAY_SHIFT)

        if beat:
            self.armed = False
            self.cnt = 0
            self.have_prev = True
        else:
            self.armed = self.armed or s < 0
            self.cnt = cnt_inc
        return beat, interval_ok, interval


class BpmCalc:
    """Validación de intervalos, promedio de 4 latidos y BPM (bpm_calc.v)."""

    def __init__(self):
        self.restart()

    def restart(self):
        self.hist = [0, 0, 0, 0]
        self.stable = 0
        self.last_n = 0
        self.bpm = 0
        self.ibi_ms = 0
        self.valid = False

    def beat(self, n):
        if n < MIN_N or n > MAX_N:
            self.stable = 0
        elif self.stable == 0 or abs(n - self.last_n) > (self.last_n >> 2):
            self.stable = 1
            self.hist = [n] + self.hist[:3]
        else:
            self.stable = min(self.stable + 1, 15)
            self.hist = [n] + self.hist[:3]
        self.last_n = n

        if self.stable >= STABLE_BEATS:
            total = sum(self.hist)
            self.bpm = (24000 + (total >> 1)) // total  # round(6000 / promedio)
            self.ibi_ms = 10 * n
            self.valid = True
        else:
            self.valid = False

    def timeout(self):
        self.stable = 0
        self.valid = False


class PpgProcessor:
    """Equivalente de ppg_processor.v, una llamada por ranura de muestra."""

    def __init__(self):
        self.filt = PpgFilter()
        self.det = PulseDetector()
        self.calc = BpmCalc()
        self.flags = 0
        self.was_valid = False

    def _restart(self):
        self.filt.restart()
        self.det.restart()
        self.calc.restart()

    def slot(self, ir, dropped=False, overflow=False):
        """Procesa una ranura de 10 ms. Devuelve el latido detectado o None."""
        beat_interval = None
        if dropped:
            self.flags |= Q_GAP
            self._restart()
        elif overflow:
            self.flags |= Q_FIFO
            self._restart()
        elif ir >= SAT_LEVEL:
            self.flags |= Q_SAT
            self._restart()
        elif ir < CONTACT_MIN:
            self.flags |= Q_CONTACT
            self._restart()
        else:
            s = self.filt.step(ir)
            beat, interval_ok, interval = self.det.step(s)
            if interval_ok:
                self.calc.beat(interval)
                beat_interval = interval
            elif beat:
                beat_interval = 0  # Primer latido tras reinicio: sin intervalo.
            if self.det.cnt > MAX_N and self.calc.stable:
                self.calc.timeout()

        valid = self.data_valid
        if valid and not self.was_valid:
            self.flags = 0  # Las banderas se limpian al recuperar una medición válida.
        self.was_valid = valid
        return beat_interval

    @property
    def low_amp(self):
        return self.det.env < MIN_AMP

    @property
    def data_valid(self):
        return self.calc.valid and not self.low_amp

    @property
    def quality(self):
        return self.flags | (Q_LOWAMP if self.low_amp else 0)
