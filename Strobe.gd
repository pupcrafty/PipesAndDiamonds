extends Node3D
class_name StrobeController

@export var on_energy: float = 5.0
@export var off_energy: float = 0.0

var _lights: Array[StrobeLight] = []

var _active: bool = false
var _frequency_hz: float = 0.0
var _duration_sec: float = 0.0
var _elapsed: float = 0.0
var _toggle_elapsed: float = 0.0
var _is_on: bool = false

var _pulse_tween: Tween


func _ready() -> void:
	_lights.clear()
	for child in get_children():
		if child is StrobeLight:
			_lights.append(child)

	print("StrobeController ready. lights_found=", _lights.size(), " path=", get_path())
	_restore_all()


# ---------------- STROBE ----------------

func start_strobe(frequency_hz: float, duration_sec: float) -> void:
	if frequency_hz <= 0.0 or duration_sec <= 0.0:
		return
	if _lights.is_empty():
		push_warning("StrobeController: No StrobeLight children found.")
		return

	_cancel_pulse()

	_frequency_hz = frequency_hz
	_duration_sec = duration_sec
	_elapsed = 0.0
	_toggle_elapsed = 0.0
	_is_on = false
	_active = true

	_apply_state()


func stop_strobe() -> void:
	if !_active:
		return
	_active = false
	_restore_all()


func _process(delta: float) -> void:
	if !_active:
		return

	_elapsed += delta
	if _elapsed >= _duration_sec:
		stop_strobe()
		return

	_toggle_elapsed += delta
	var toggle_interval: float = 1.0 / (_frequency_hz * 2.0)

	while _toggle_elapsed >= toggle_interval:
		_toggle_elapsed -= toggle_interval
		_is_on = !_is_on
		_apply_state()


func _apply_state() -> void:
	var e := on_energy if _is_on else off_energy
	for l in _lights:
		l.set_strobe_energy(e)


# ---------------- PULSE ----------------

func pulse(peak_energy: float, duration_sec: float) -> void:
	if duration_sec <= 0.0:
		return
	if _lights.is_empty():
		push_warning("StrobeController: No StrobeLight children found.")
		return

	print("StrobeController.pulse peak=", peak_energy, " duration=", duration_sec)

	stop_strobe()
	_cancel_pulse()

	var half: float = duration_sec * 0.5

	_pulse_tween = create_tween()
	_pulse_tween.set_trans(Tween.TRANS_SINE)
	_pulse_tween.set_ease(Tween.EASE_IN_OUT)
	_pulse_tween.set_parallel(true)

	# Make every light do: up (0..half) then down (half..duration) IN PARALLEL
	for l in _lights:
		_pulse_tween.tween_property(l, "light_energy", peak_energy, half)
		_pulse_tween.tween_property(l, "light_energy", l._base_energy, half).set_delay(half)

	_pulse_tween.finished.connect(_restore_all)


func _cancel_pulse() -> void:
	if _pulse_tween and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = null


func _restore_all() -> void:
	for l in _lights:
		l.restore_energy()
