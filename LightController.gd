extends Node
class_name LightController

@export var osc_path: NodePath
@export var analyzer_path: NodePath

var _osc: OscClockReceiver
var _analyzer: SpectrumAudioAnalyzer

func _ready() -> void:
	_osc = _get_osc()
	_analyzer = _get_analyzer()

	if _osc != null:
		_osc.beat.connect(_on_osc_beat)
		_osc.bpm_changed.connect(_on_osc_bpm_changed)
		_osc.confidence_changed.connect(_on_osc_confidence_changed)
	else:
		push_warning("LightController: OscClockReceiver not found.")

	if _analyzer != null:
		_analyzer.spectrum_cues.connect(_on_spectrum_cues)
		_analyzer.standardized_cues.connect(_on_standardized_cues)
	else:
		push_warning("LightController: SpectrumAudioAnalyzer not found.")


func _on_osc_beat(beat_id: int) -> void:
	_log_event("osc", "beat", {"beat_id": beat_id})


func _on_osc_bpm_changed(bpm: float) -> void:
	_log_event("osc", "bpm_changed", {"bpm": bpm})


func _on_osc_confidence_changed(confidence: float) -> void:
	_log_event("osc", "confidence_changed", {"confidence": confidence})


func _on_spectrum_cues(bass: float, mid: float, treble: float, beat: bool, pulse: bool, movement: float) -> void:
	_log_event(
		"audio",
		"spectrum_cues",
		{
			"bass": bass,
			"mid": mid,
			"treble": treble,
			"beat": beat,
			"pulse": pulse,
			"movement": movement
		}
	)


func _on_standardized_cues(payload: Dictionary) -> void:
	_log_event("audio", "standardized_cues", payload)


func _log_event(source: String, event_name: String, payload: Dictionary) -> void:
	var entry := {
		"source": source,
		"event": event_name,
		"payload": payload,
		"timestamp_ms": Time.get_ticks_msec()
	}
	print(JSON.stringify(entry))
	print("[%s]:[%s]:%s" % [source, event_name, _format_payload(payload)])


func _format_payload(payload: Dictionary) -> String:
	if payload.is_empty():
		return ""
	var keys := payload.keys()
	keys.sort()
	var parts: Array[String] = []
	for key in keys:
		var value = payload[key]
		if value is float:
			parts.append("%s=%s" % [key, snappedf(value, 0.0001)])
		else:
			parts.append("%s=%s" % [key, value])
	return "{" + ", ".join(parts) + "}"


func _get_osc() -> OscClockReceiver:
	if osc_path != NodePath(""):
		return get_node_or_null(osc_path) as OscClockReceiver
	var nodes: Array[Node] = get_tree().get_root().find_children("", "OscClockReceiver", true, false)
	return nodes[0] as OscClockReceiver if not nodes.is_empty() else null


func _get_analyzer() -> SpectrumAudioAnalyzer:
	if analyzer_path != NodePath(""):
		return get_node_or_null(analyzer_path) as SpectrumAudioAnalyzer
	var by_name := get_node_or_null("MicPlayer") as SpectrumAudioAnalyzer
	if by_name != null:
		return by_name
	var nodes: Array[Node] = get_tree().get_root().find_children("", "SpectrumAudioAnalyzer", true, false)
	return nodes[0] as SpectrumAudioAnalyzer if not nodes.is_empty() else null
