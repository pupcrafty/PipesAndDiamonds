extends Node

@onready var osc: OscClockReceiver = $OscClockReceiver

func _ready() -> void:
	print("Children:", get_children());
	osc.beat.connect(_on_beat)
	osc.bpm_changed.connect(_on_bpm)
	osc.confidence_changed.connect(_on_conf)
func _process(delta) -> void:
	if osc == null:
		print("OSC not available")
	

func _on_beat(id: int) -> void:
	print("BEAT ", id)

func _on_bpm(b: float) -> void:
	print("BPM ", b)

func _on_conf(c: float) -> void:
	print("CONF ", c)
