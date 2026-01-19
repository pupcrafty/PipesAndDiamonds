extends Node
class_name LightController

func _ready() -> void:
	var a := get_node_or_null("MicPlayer") as SpectrumAudioAnalyzer
	if a == null:
		push_error("LightController: MicPlayer missing SpectrumAudioAnalyzer.gd")
		return
	a.spectrum_cues.connect(_on_spec)

func _on_spec(bass: float, mid: float, treble: float, beat: bool, pulse: bool, movement: float) -> void:
	if beat or pulse:
		print("bass=", snappedf(bass, 0.001),
			  " mid=", snappedf(mid, 0.001),
			  " treble=", snappedf(treble, 0.001),
			  " beat=", beat,
			  " pulse=", pulse,
			  " move=", snappedf(movement, 0.0001))
