extends Node
class_name LightController

@export var strobe_path: NodePath = NodePath("Strobe")

# Make it obvious for testing
@export var pulse_duration_sec: float = 0.20
@export var pulse_peak_min: float = 6.0
@export var pulse_peak_max: float = 20.0

# How strongly bass influences peak (bigger = more dramatic)
@export var bass_to_peak_scale: float = 40.0

@export var pulse_cooldown_sec: float = 0.10

var _strobe: StrobeController
var _pulse_cd: float = 0.0


func _ready() -> void:
	_strobe = get_node_or_null(strobe_path) as StrobeController
	print("LightController ready. strobe_path=", strobe_path, " strobe_found=", _strobe != null)
	if _strobe == null:
		push_warning("LightController: StrobeController not found at strobe_path = " + str(strobe_path))

	var a := get_node_or_null("MicPlayer") as SpectrumAudioAnalyzer
	if a == null:
		push_error("LightController: MicPlayer missing SpectrumAudioAnalyzer.gd")
		return

	a.spectrum_cues.connect(_on_spec)
	print("LightController: connected to spectrum_cues")


func _process(delta: float) -> void:
	if _pulse_cd > 0.0:
		_pulse_cd = maxf(0.0, _pulse_cd - delta)


func _on_spec(bass: float, mid: float, treble: float, beat: bool, pulse: bool, movement: float) -> void:
	# you already see this print - keep it
	if beat or pulse:
		print("bass=", snappedf(bass, 0.001),
			  " mid=", snappedf(mid, 0.001),
			  " treble=", snappedf(treble, 0.001),
			  " beat=", beat,
			  " pulse=", pulse,
			  " move=", snappedf(movement, 0.0001))

	# For now: fire on either cue so we can validate the pipeline
	if (pulse or beat) and _strobe != null and _pulse_cd <= 0.0:
		# bass values are tiny (~0.01–0.03), so scale hard to make it visible
		var strength := clampf(bass * bass_to_peak_scale, 0.0, 1.0)
		var peak := lerpf(pulse_peak_min, pulse_peak_max, strength)

		print("LightController: firing strobe.pulse peak=", peak)
		_strobe.pulse(peak, pulse_duration_sec)
		_pulse_cd = pulse_cooldown_sec
