extends Node
class_name OscClockReceiver

signal bpm_changed(bpm: float)
signal confidence_changed(confidence: float)
signal beat(beat_id: int)
signal spectrum_cues(bass: float, mid: float, treble: float, beat: bool, pulse: bool, movement: float)
signal standardized_cues(payload: Dictionary)
signal phrase_changed(phrase: String)

@export var listen_port: int = 9000

var udp: PacketPeerUDP = PacketPeerUDP.new()

var bpm: float = 120.0
var confidence: float = 0.0
var beat_id: int = 0
var _audio_payload: Dictionary = {
	"bass": 0.0,
	"mid": 0.0,
	"treble": 0.0,
	"beat": false,
	"pulse": false,
	"movement": 0.0,
	"total_energy": 0.0,
	"energy_delta": 0.0,
	"energy_variance": 0.0,
	"bass_ratio": 0.0,
	"mid_ratio": 0.0,
	"treble_ratio": 0.0,
	"band_balance": 0.0
}
var _current_phrase: String = ""

func _ready() -> void:
	var err: int = udp.bind(listen_port)
	if err != OK:
		push_error("OSC bind failed on port %d (err=%d)" % [listen_port, err])
		return
	print("OSC listening on UDP port ", listen_port)

func _process(_delta: float) -> void:
	while udp.get_available_packet_count() > 0:
		var packet: PackedByteArray = udp.get_packet()
		_parse_packet(packet)

# ============================================================
# Typed result objects (avoid returning null / Variant)
# ============================================================

class OscStringRead:
	var ok: bool = false
	var value: String = ""
	var next_index: int = 0

class OscMsg:
	var address: String = ""
	var args: Array[Variant] = []

class OscMsgRead:
	var ok: bool = false
	var msg: OscMsg = OscMsg.new()

# ============================================================
# Packet parsing
# ============================================================

func _parse_packet(data: PackedByteArray) -> void:
	# Bundles start with "#bundle"
	if data.size() >= 8:
		# "#bundle" is 7 chars; bundle tag in OSC is "#bundle\0"
		var maybe: String = data.slice(0, 7).get_string_from_ascii()
		if maybe == "#bundle":
			_parse_bundle(data)
			return

	var msg_read: OscMsgRead = _read_message(data, 0)
	if not msg_read.ok:
		return
	_handle_message(msg_read.msg)

func _parse_bundle(data: PackedByteArray) -> void:
	var idx: int = 0

	var tag: OscStringRead = _read_osc_string(data, idx)
	if not tag.ok or tag.value != "#bundle":
		return
	idx = tag.next_index

	# timetag (8 bytes)
	if idx + 8 > data.size():
		return
	idx += 8

	# Elements: [int32 size][bytes...]
	while idx + 4 <= data.size():
		var size: int = _read_i32(data, idx)
		idx += 4
		if size <= 0:
			return
		if idx + size > data.size():
			return

		var element: PackedByteArray = data.slice(idx, idx + size)
		idx += size
		_parse_packet(element)

func _read_message(data: PackedByteArray, start_index: int) -> OscMsgRead:
	var out: OscMsgRead = OscMsgRead.new()
	var idx: int = start_index

	var addr: OscStringRead = _read_osc_string(data, idx)
	if not addr.ok:
		return out
	idx = addr.next_index

	var tags: OscStringRead = _read_osc_string(data, idx)
	if not tags.ok:
		return out
	idx = tags.next_index

	if tags.value.length() < 2:
		return out
	if tags.value[0] != ",":
		return out

	var msg: OscMsg = OscMsg.new()
	msg.address = addr.value
	msg.args = []

	for i: int in range(1, tags.value.length()):
		var t: String = tags.value[i]

		match t:
			"i":
				if idx + 4 > data.size():
					return out
				msg.args.append(_read_i32(data, idx))
				idx += 4

			"f":
				if idx + 4 > data.size():
					return out
				msg.args.append(_read_f32(data, idx))
				idx += 4

			"s":
				var s: OscStringRead = _read_osc_string(data, idx)
				if not s.ok:
					return out
				msg.args.append(s.value)
				idx = s.next_index

			_:
				# Unsupported typetag: bail safely
				return out

	out.ok = true
	out.msg = msg
	return out

func _handle_message(msg: OscMsg) -> void:
	var address: String = msg.address
	var args: Array[Variant] = msg.args

	match address:
		"/clock/beat":
			if args.size() >= 1 and args[0] is int:
				beat_id = args[0] as int
				emit_signal("beat", beat_id)

		"/clock/bpm":
			if args.size() >= 1 and (args[0] is float or args[0] is int):
				bpm = float(args[0])
				emit_signal("bpm_changed", bpm)

		"/clock/conf":
			if args.size() >= 1 and (args[0] is float or args[0] is int):
				confidence = float(args[0])
				emit_signal("confidence_changed", confidence)

		"/clock/beat_id":
			if args.size() >= 1 and args[0] is int:
				beat_id = args[0] as int

		"/clock/time":
			# optional: float unix time; ignore or use for diagnostics
			pass

		"/audio/standardized":
			if args.size() >= 1 and args[0] is String:
				var parsed: Variant = JSON.parse_string(args[0])
				if parsed is Dictionary:
					_apply_standardized_payload(parsed)

		"/audio/bass":
			_update_audio_payload("bass", args)
		"/audio/mid":
			_update_audio_payload("mid", args)
		"/audio/treble":
			_update_audio_payload("treble", args)
		"/audio/beat":
			_update_audio_payload("beat", args)
		"/audio/pulse":
			_update_audio_payload("pulse", args)
		"/audio/movement":
			_update_audio_payload("movement", args)
		"/audio/total_energy":
			_update_audio_payload("total_energy", args)
		"/audio/energy_delta":
			_update_audio_payload("energy_delta", args)
		"/audio/energy_variance":
			_update_audio_payload("energy_variance", args)
		"/audio/bass_ratio":
			_update_audio_payload("bass_ratio", args)
		"/audio/mid_ratio":
			_update_audio_payload("mid_ratio", args)
		"/audio/treble_ratio":
			_update_audio_payload("treble_ratio", args)
		"/audio/band_balance":
			_update_audio_payload("band_balance", args)

		"/phrase/current":
			if args.size() >= 1 and args[0] is String:
				var phrase := args[0]
				if phrase != _current_phrase:
					_current_phrase = phrase
					emit_signal("phrase_changed", phrase)

		_:
			# Uncomment for debugging:
			# print("OSC:", address, args)
			pass

# ============================================================
# OSC primitive readers (typed)
# ============================================================

func _read_osc_string(data: PackedByteArray, idx: int) -> OscStringRead:
	var out: OscStringRead = OscStringRead.new()

	if idx < 0 or idx >= data.size():
		return out

	# Find null terminator
	var end: int = idx
	while end < data.size() and data[end] != 0:
		end += 1
	if end >= data.size():
		return out

	out.value = data.slice(idx, end).get_string_from_utf8()

	end += 1 # consume null terminator

	# Pad to 4-byte boundary
	while (end % 4) != 0:
		end += 1
	if end > data.size():
		return out

	out.ok = true
	out.next_index = end
	return out

func _read_i32(data: PackedByteArray, idx: int) -> int:
	# Big-endian int32
	var b0: int = int(data[idx])
	var b1: int = int(data[idx + 1])
	var b2: int = int(data[idx + 2])
	var b3: int = int(data[idx + 3])
	var u: int = (b0 << 24) | (b1 << 16) | (b2 << 8) | b3

	# Convert unsigned -> signed
	if (u & 0x80000000) != 0:
		return int(u - 0x100000000)
	return u

func _read_u32(data: PackedByteArray, idx: int) -> int:
	var b0: int = int(data[idx])
	var b1: int = int(data[idx + 1])
	var b2: int = int(data[idx + 2])
	var b3: int = int(data[idx + 3])
	return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3

func _read_f32(data: PackedByteArray, idx: int) -> float:
	# Big-endian float32 via StreamPeerBuffer (typed + safe)
	var u: int = _read_u32(data, idx)

	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(4)
	bytes[0] = (u >> 24) & 0xFF
	bytes[1] = (u >> 16) & 0xFF
	bytes[2] = (u >> 8) & 0xFF
	bytes[3] = u & 0xFF

	var sp: StreamPeerBuffer = StreamPeerBuffer.new()
	sp.big_endian = true
	sp.data_array = bytes
	sp.seek(0)
	return sp.get_float()


func _apply_standardized_payload(payload: Dictionary) -> void:
	for key in payload.keys():
		_audio_payload[key] = payload[key]
	_emit_audio_signals()


func _update_audio_payload(key: String, args: Array[Variant]) -> void:
	if args.size() < 1:
		return
	var value: Variant = args[0]
	if key == "beat" or key == "pulse":
		_audio_payload[key] = bool(value) if value is bool else (float(value) > 0.0)
	else:
		_audio_payload[key] = float(value)
	_emit_audio_signals()


func _emit_audio_signals() -> void:
	standardized_cues.emit(_audio_payload.duplicate())
	spectrum_cues.emit(
		float(_audio_payload.get("bass", 0.0)),
		float(_audio_payload.get("mid", 0.0)),
		float(_audio_payload.get("treble", 0.0)),
		bool(_audio_payload.get("beat", false)),
		bool(_audio_payload.get("pulse", false)),
		float(_audio_payload.get("movement", 0.0))
	)
