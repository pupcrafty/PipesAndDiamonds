extends Node3D
class_name LightController

enum RouteMode { ALTERNATE, RANDOM }

@export var route_mode: RouteMode = RouteMode.ALTERNATE
@export var avoid_repeat: bool = true           # for RANDOM mode: don't pick same rig twice in a row
@export var fanout: int = 1                     # 1 = one rig per cue, 2 = two rigs per cue, etc.

# Baseline motion for all rigs (keeps a gentle show even between cues)
@export var base_rotation_speed: float = 6.0
@export var base_push_speed: float = 0.03
@export var base_intensity: float = 0.0         # around your normal brightness
@export var intensity_follow: float = 6.0       # how fast it chases the target (bigger = snappier)

@export var beat_intensity_target_boost: float = 1.8
@export var pulse_intensity_target_boost: float = 2.6

# Cue -> impulse strengths
@export var beat_intensity_boost: float = 1.3
@export var beat_push_boost: float = 0.30
@export var beat_rotation_kick: float = 18.0

@export var pulse_intensity_flash: float = 2.0
@export var pulse_rotation_kick: float = 80.0
@export var pulse_push_kick: float = 0.22

@export var movement_rotation_bias: float = 16.0
@export var movement_push_bias: float = 0.10

# Decay rates (bigger = faster decay)
@export var beat_decay: float = 7.0
@export var pulse_decay: float = 10.0
@export var movement_decay: float = 2.0

@export var master_scale: float = 1.0

var _rigs: Array[PartyLightColorRig] = []

# Per-rig state
class RigState:
	var beat: float = 0.0
	var pulse: float = 0.0
	var move: float = 0.0  # signed
	var last_kind: String = ""

var _state: Array[RigState] = []

# Routing helpers
var _rr_index: int = 0
var _last_pick: int = -1

func _ready() -> void:
	_collect_rigs(self)
	if _rigs.is_empty():
		push_error("LightController: No PartyLightColorRig children found.")
		return

	_state.clear()
	for i in range(_rigs.size()):
		_state.append(RigState.new())

	var analyzer := get_node_or_null("MicPlayer")
	if analyzer == null:
		push_error("LightController: No child named 'MicPlayer'.")
		return
	if analyzer.has_signal("cue"):
		analyzer.connect("cue", Callable(self, "_on_cue"))
	else:
		push_error("LightController: MicPlayer script has no 'cue' signal.")

	randomize()

func _process(delta: float) -> void:
	if _rigs.is_empty():
		return

	for i in range(_rigs.size()):
		var s := _state[i]

		# Decay
		s.beat = _decay_to_zero(s.beat, beat_decay, delta)
		s.pulse = _decay_to_zero(s.pulse, pulse_decay, delta)
		s.move = _decay_to_zero(s.move, movement_decay, delta)

		# Build deltas for THIS rig from its own cues
		var beat_intensity := s.beat * beat_intensity_boost
		var beat_push := s.beat * beat_push_boost
		var beat_rot := s.beat * beat_rotation_kick

		var pulse_intensity := s.pulse * pulse_intensity_flash
		var pulse_push := s.pulse * pulse_push_kick
		var pulse_rot := s.pulse * pulse_rotation_kick

		var move_rot := s.move * movement_rotation_bias
		var move_push := s.move * movement_push_bias

		var intensity_delta: float = (base_intensity_speed + beat_intensity + pulse_intensity) * delta * master_scale
		var push_delta: float = (base_push_speed + beat_push + pulse_push + move_push) * delta * master_scale
		var rotation_delta: float = (base_rotation_speed + beat_rot + pulse_rot + move_rot) * delta * master_scale

		_rigs[i].update(push_delta, rotation_delta, intensity_delta)

func _on_cue(kind: String, strength: float, bpm: float, meta: Dictionary) -> void:
	if _rigs.is_empty():
		return

	# Choose which rig(s) get this cue
	var targets := _pick_targets(max(1, fanout))

	for idx in targets:
		var s := _state[idx]

		if kind == "beat":
			s.beat = clamp(s.beat + strength, 0.0, 3.0)
			s.last_kind = "beat"

		elif kind == "pulse":
			s.pulse = clamp(s.pulse + strength, 0.0, 3.0)
			s.last_kind = "pulse"

		elif kind == "movement_up":
			s.move = clamp(s.move + strength * 0.6, -2.0, 2.0)
			s.last_kind = "movement"

		elif kind == "movement_down":
			s.move = clamp(s.move - strength * 0.6, -2.0, 2.0)
			s.last_kind = "movement"

		elif kind == "movement_flat":
			s.move *= 0.9

func _pick_targets(count: int) -> Array[int]:
	var out: Array[int] = []
	var n := _rigs.size()
	if n <= 0:
		return out

	count = clamp(count, 1, n)

	if route_mode == RouteMode.ALTERNATE:
		for k in range(count):
			var idx := (_rr_index + k) % n
			out.append(idx)
		_rr_index = (_rr_index + count) % n
		return out

	# RANDOM
	var tries := 0
	while out.size() < count and tries < 50:
		tries += 1
		var idx := randi() % n

		if avoid_repeat and count == 1 and _last_pick == idx:
			continue
		if idx in out:
			continue

		out.append(idx)

	if out.size() > 0:
		_last_pick = out[0]
	return out

func _decay_to_zero(x: float, rate: float, delta: float) -> float:
	var k: float = clamp(rate * delta, 0.0, 1.0)
	return lerp(x, 0.0, k)

func _collect_rigs(n: Node) -> void:
	if n is PartyLightColorRig:
		_rigs.append(n as PartyLightColorRig)
	for c: Node in n.get_children():
		_collect_rigs(c)
