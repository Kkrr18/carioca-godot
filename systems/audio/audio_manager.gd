class_name AudioManager
extends Node

## Ambiência sonora sintetizada.
##
## O projeto não tem arquivo de áudio nenhum e ainda assim precisa de ambiente:
## ruído filtrado em tempo real por AudioStreamGenerator. Um ruído branco
## filtrado passa por vento; integrado, vira rumor de trânsito; com corte curto e
## ganho baixo, vira o zumbido de dentro de casa. Custa uma fração de CPU porque
## roda em 22 kHz e só enche o buffer que a placa pediu.
##
## Quando entra trilha ou som gravado, o barramento já está separado e o synth
## continua como camada de base — dá para abaixar ou desligar pelo perfil.

const MIX_RATE := 22050
const MAX_FRAMES_PER_TICK := 2048

var enabled: bool = true
var mode: String = "street"
var volume_db: float = -15.0

var _player: AudioStreamPlayer = null
var _generator: AudioStreamGenerator = null
var _playback: AudioStreamGeneratorPlayback = null
var _low: float = 0.0
var _brown: float = 0.0
var _hum_phase: float = 0.0


func _ready() -> void:
	var settings := CariocaSettings.get_instance()
	enabled = settings.ambience_enabled
	volume_db = linear_to_db(clampf(settings.master_volume, 0.0, 1.0)) - 12.0
	_generator = AudioStreamGenerator.new()
	_generator.mix_rate = MIX_RATE
	_generator.buffer_length = 0.3
	_player = AudioStreamPlayer.new()
	_player.name = "Ambience"
	_player.stream = _generator
	_player.volume_db = volume_db
	add_child(_player)
	_player.play()


func set_mode(new_mode: String) -> void:
	mode = new_mode


func _process(_delta: float) -> void:
	if not enabled or not is_inside_tree():
		return
	if _playback == null:
		if _player == null or not _player.playing:
			return
		_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback
		if _playback == null:
			return
	var available := _playback.get_frames_available()
	if available <= 0:
		return
	var frames := mini(available, MAX_FRAMES_PER_TICK)
	var cutoff := _cutoff()
	var gain := _gain()
	var tone := _tone()
	for i in range(frames):
		if not _playback.can_push_frame():
			break
		var white := randf() * 2.0 - 1.0
		_brown += (white - _brown) * 0.02
		_low += (white - _low) * cutoff
		_hum_phase = fposmod(_hum_phase + tone / float(MIX_RATE), 1.0)
		var sample := _low * gain
		sample += _brown * gain * 0.9
		if tone > 0.0:
			sample += sin(_hum_phase * TAU) * gain * 0.12
		sample = clampf(sample, -1.0, 1.0)
		_playback.push_frame(Vector2(sample, sample))


func _cutoff() -> float:
	match mode:
		"rain":
			return 0.30
		"interior":
			return 0.05
		_:
			return 0.12


func _gain() -> float:
	match mode:
		"rain":
			return 0.22
		"interior":
			return 0.05
		_:
			return 0.14


## Frequência do zumbido interno; 0 desliga o tom.
func _tone() -> float:
	if mode == "interior":
		return 60.0
	if mode == "rain":
		return 0.0
	return 42.0


func is_playing() -> bool:
	return _player != null and _player.playing
