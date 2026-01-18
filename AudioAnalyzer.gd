extends AudioStreamPlayer
class_name AudioAnalyzer

signal cue(kind: String, strength: float, bpm: float, meta: Dictionary)

@export var mic_bus_name: String = "Mic"
@export var force_input_device: String = "Microphone (HyperX QuadCast)"

# Feature shaping
@export var gain: float = 2.0
@export var noise_gate: float = 0.005

# Smoothing
@export var rms_smooth: float = 0.20          # 0..1
@export var env_speed: float = 0.06           # 0..1 (slow envelope = “bass-ish”)

# Pulse detection (spikes)
@export var pulse_thresh: float = 0.020       # detail threshold for pulse
@export var pulse_refractory: float = 0.08    # seconds

# Beat detection / tempo lock
@export var beat_min_bpm: float = 80.0
@export var beat_max_bpm: float = 160.0
@export var beat_lock_strength: float = 0.18  # 0..1 (higher = steadier BPM)
@export var beat_trigger_k: float = 1.6       # threshold factor vs envelope
@export var beat_refractory: float = 0.22     # seconds (prevents double hits)

# Movement (trend)
@export var movement_slope_thresh: float = 0.006  # how strong slope must be
@export var movement_emit_hz: float = 8.0         # how often to emit movement cue

var _cap: AudioEffectCapture

# running features
var _rms_s: float = 0.0
var _env: float = 0.0
var _detail_s: float = 0.0

# pulse state
var _pulse_cd: float = 0.0

# beat state
var _beat_cd: float = 0.0
var _last_beat_time: float = -999.0
var _bpm: float = 120.0
var _beat_phase: float = 0.0  # 0..1 between beats (optional for later)

# movement state
var _move_t: float = 0.0
var _prev_rms_for_slope: float = 0.0

func _ready() -> void:
	if force_input_device != "":
		AudioServer.input_device = force_input_device
	if not playing:
		play()

	_cap = _get_capture(mic_bus_name)
	if _cap == null:
		push_error("AudioAnalyzer: No AudioEffectCapture on bus: %s" % mic_bus_name)
		set_process(false)
		return

func _process(delta: float) -> void:
	if _cap == null:
		return

	_pulse_cd = max(_pulse_cd - delta, 0.0)
	_beat_cd = max(_beat_cd - delta, 0.0)

	var n: int = _cap.get_frames_available()
	if n <= 0:
		return

	var frames: PackedVector2Array = _cap.get_buffer(n)
	var rms: float = _rms(frames) * gain
	if rms < noise_gate:
		rms = 0.0

	# Envelope + “detail”
	_env += (rms - _env) * env_speed
	var detail: float = max(rms - _env, 0.0)

	# Smooth some features used for decisions
	_rms_s = lerp(_rms_s, rms, rms_smooth)
	_detail_s = lerp(_detail_s, detail, rms_smooth)

	# 1) PULSE cue (spike)
	_try_pulse()

	# 2) BEAT cue (steady)
	_try_beat(delta)

	# 3) MOVEMENT cue (trend up/down/flat)
	_try_movement(delta)

func _try_pulse() -> void:
	if _pulse_cd > 0.0:
		return
	if _detail_s >= pulse_thresh:
		_pulse_cd = pulse_refractory
		var strength: float = clamp(_detail_s / max(0.0001, pulse_thresh), 0.0, 4.0)
		cue.emit("pulse", strength, _bpm, {
			"rms": _rms_s,
			"env": _env,
			"detail": _detail_s
		})

func _try_beat(delta: float) -> void:
	# Beat trigger uses a relative threshold so it adapts to loudness.
	# If RMS rises above envelope by a factor, we consider it a candidate hit.
	if _beat_cd > 0.0:
		_update_phase(delta)
		return

	var thresh: float = _env * beat_trigger_k + pulse_thresh * 0.4
	if _rms_s >= thresh and _rms_s > 0.0:
		# candidate beat hit
		var now := Time.get_ticks_msec() / 1000.0
		var dt := now - _last_beat_time

		# accept only if interval maps to a plausible BPM
		if dt > 0.0001:
			var bpm_inst := 60.0 / dt
			if bpm_inst >= beat_min_bpm and bpm_inst <= beat_max_bpm:
				# lock to a steady bpm (low-pass)
				_bpm = lerp(_bpm, bpm_inst, beat_lock_strength)
				_last_beat_time = now
				_beat_cd = beat_refractory
				_beat_phase = 0.0

				var strength:float= clamp((_rms_s - thresh) / max(0.0001, thresh), 0.0, 4.0)
				cue.emit("beat", strength, _bpm, {
					"rms": _rms_s,
					"env": _env,
					"thresh": thresh
				})
	_update_phase(delta)

func _update_phase(delta: float) -> void:
	# Optional: phase progresses based on the locked bpm (useful later)
	var period: float= 60.0 / max(1.0, _bpm)
	_beat_phase = fmod(_beat_phase + delta / max(0.0001, period), 1.0)

func _try_movement(delta: float) -> void:
	_move_t += delta
	if _move_t < (1.0 / max(1.0, movement_emit_hz)):
		return
	_move_t = 0.0

	var slope: float = _rms_s - _prev_rms_for_slope
	_prev_rms_for_slope = _rms_s

	var kind := "flat"
	if slope > movement_slope_thresh:
		kind = "up"
	elif slope < -movement_slope_thresh:
		kind = "down"

	# strength is magnitude of slope normalized
	var strength: float = clamp(abs(slope) / max(0.0001, movement_slope_thresh), 0.0, 4.0)
	cue.emit("movement_" + kind, strength, _bpm, {
		"slope": slope,
		"rms": _rms_s,
		"phase": _beat_phase
	})

func _get_capture(bus_name: String) -> AudioEffectCapture:
	var bus: int = AudioServer.get_bus_index(bus_name)
	if bus == -1:
		push_error("AudioAnalyzer: Mic bus not found: %s" % bus_name)
		return null
	for i: int in range(AudioServer.get_bus_effect_count(bus)):
		var fx: AudioEffect = AudioServer.get_bus_effect(bus, i)
		if fx is AudioEffectCapture:
			return fx as AudioEffectCapture
	return null

func _rms(frames: PackedVector2Array) -> float:
	var sum: float = 0.0
	for s: Vector2 in frames:
		var v: float = (abs(s.x) + abs(s.y)) * 0.5
		sum += v * v
	return sqrt(sum / max(1.0, float(frames.size())))
