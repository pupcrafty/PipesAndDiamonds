extends Node
class_name LightController

signal osc_beat(beat_id: int)
signal osc_bpm_changed(bpm: float)
signal osc_confidence_changed(confidence: float)
signal spectrum_cues(bass: float, mid: float, treble: float, beat: bool, pulse: bool, movement: float)
signal standardized_cues(payload: Dictionary)

@export var osc_path: NodePath
@export var analyzer_path: NodePath
@export var phrase_detector_path: NodePath

var _osc: OscClockReceiver
var _analyzer: SpectrumAudioAnalyzer
var _phrase_detector: PhraseInspector
var current_phrase: String = "SILENCE / VOID"

func _ready() -> void:
	_osc = _get_osc()
	_analyzer = _get_analyzer()

	if _osc != null:
		_osc.beat.connect(_on_osc_beat)
		_osc.bpm_changed.connect(_on_osc_bpm_changed)
		_osc.confidence_changed.connect(_on_osc_confidence_changed)
		if _osc.has_signal("spectrum_cues"):
			_osc.spectrum_cues.connect(_on_spectrum_cues)
		if _osc.has_signal("standardized_cues"):
			_osc.standardized_cues.connect(_on_standardized_cues)
		if _osc.has_signal("phrase_changed"):
			_osc.phrase_changed.connect(_on_phrase_changed)
	else:
		push_warning("LightController: OscClockReceiver not found.")

	if _osc == null:
		if _analyzer != null:
			_analyzer.spectrum_cues.connect(_on_spectrum_cues)
			_analyzer.standardized_cues.connect(_on_standardized_cues)
		else:
			push_warning("LightController: SpectrumAudioAnalyzer not found.")

		_phrase_detector = _get_phrase_detector()
		if _phrase_detector != null:
			_phrase_detector.phrase_changed.connect(_on_phrase_changed)
		else:
			push_warning("LightController: PhraseInspector not found.")


func _on_osc_beat(beat_id: int) -> void:
	osc_beat.emit(beat_id)


func _on_osc_bpm_changed(bpm: float) -> void:
	osc_bpm_changed.emit(bpm)


func _on_osc_confidence_changed(confidence: float) -> void:
	osc_confidence_changed.emit(confidence)


func _on_spectrum_cues(bass: float, mid: float, treble: float, beat: bool, pulse: bool, movement: float) -> void:
	spectrum_cues.emit(bass, mid, treble, beat, pulse, movement)


func _on_standardized_cues(payload: Dictionary) -> void:
	standardized_cues.emit(payload)


func _on_phrase_changed(phrase: String) -> void:
	if phrase == current_phrase:
		return
	current_phrase = phrase
	print("[phrase]:%s" % phrase)


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


func _get_phrase_detector() -> PhraseInspector:
	if phrase_detector_path != NodePath(""):
		return get_node_or_null(phrase_detector_path) as PhraseInspector
	var nodes: Array[Node] = get_tree().get_root().find_children("", "PhraseInspector", true, false)
	return nodes[0] as PhraseInspector if not nodes.is_empty() else null
