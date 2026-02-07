extends Node

## Audio Service Listener (Test)
##
## Attach this script to a Node that has an AudioServiceOSC child node.
## It subscribes to key endpoints and prints when messages arrive.

@export var osc_receiver_path: NodePath = NodePath("AudioServiceOSC")

# Endpoints to verify data flow
const REQUIRED_ENDPOINTS: Array[String] = [
	"/clock/beat",
	"/clock/beat_id",
	"/clock/bpm",
	"/clock/conf",
	"/audio/bass",
	"/audio/mid",
	"/audio/treble",
	"/audio/total_energy",
	"/audio/energy_delta",
	"/audio/movement",
	"/audio/beat",
	"/audio/pulse",
	"/audio/band_normalized_bass_1",
	"/audio/band_normalized_mid_1",
	"/audio/band_normalized_high_2",
	"/audio/band_presence_bass_1",
	"/audio/band_presence_mid_1",
	"/audio/band_presence_high_2",
	"/audio/beat_norm_band_win_30",
	"/audio/beat_norm_band_win_60",
]

var _osc_receiver: Node
var _last_print_time: float = 0.0

func _ready() -> void:
	_osc_receiver = get_node_or_null(osc_receiver_path)
	if _osc_receiver == null:
		push_error("AudioServiceListener: AudioServiceOSC node not found. Set osc_receiver_path.")
		return
	
	# Ensure we subscribe to all required endpoints
	for endpoint in REQUIRED_ENDPOINTS:
		_osc_receiver.subscribe_to_endpoint(endpoint)
	
	# Connect to updates signal
		if _osc_receiver.has_signal("endpoint_updated"):
			_osc_receiver.endpoint_updated.connect(_on_endpoint_updated)
		else:
			push_error("AudioServiceListener: AudioServiceOSC missing endpoint_updated signal.")

func _on_endpoint_updated(endpoint_name: String, value: Variant) -> void:
	# Placeholder: you can inspect `value` in the debugger if needed.
	_last_print_time = Time.get_ticks_msec() / 1000.0
