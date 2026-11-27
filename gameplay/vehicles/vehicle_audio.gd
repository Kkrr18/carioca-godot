class_name VehicleAudio
extends Node

## Som do veículo — placeholders sintetizados, arquitetura pronta.
##
## O CARIOCA não tem nenhum arquivo de áudio: a ambiência da Etapa 1 é
## sintetizada em tempo real (AudioManager). O veículo segue a mesma linha, com
## uma diferença importante declarada: **estes sons não são realistas** — são
## placeholders funcionais que dão resposta imediata ao jogador:
##
##   - motor: tom grave contínuo cujo pitch sobe com a velocidade e o pé;
##   - buzina: quadrada de 420 Hz, dois tons levemente desafinados (o clássico
##     "fi-fó" de carro popular), gerada em buffer no _ready;
##   - freio: o mesmo ruído da chuva do AudioManager, reusado em modo curto.
##
## Cada veículo dirigido tem um nó deste tipo como filho. Sem motorista, o
## motor em marcha lenta continua, porque o carro "ligado" faz parte da leitura
## de que o carro está lá.
##
## Quando entrarem gravações reais (rPM loop, derrapagem, colisão), o contrato
## é trocar os streams, não a API: `update_engine`, `set_horn`, `skid`.

const MIX_RATE := 22050
const ENGINE_BASE_HZ := 55.0
const ENGINE_MAX_HZ := 210.0
const HORN_SECONDS := 0.6
const HORN_F0 := 420.0
const HORN_F1 := 528.0

var enabled: bool = true

var _engine_player: AudioStreamPlayer = null
var _engine_stream: AudioStreamGenerator = null
var _engine_playback: AudioStreamGeneratorPlayback = null
var _horn_player: AudioStreamPlayer = null
var _phase: float = 0.0
var _engine_level: float = 0.0
var _target_level: float = 0.0
var _horn_on: bool = false


## Matemática pura do tom do motor — é isto que o teste exercita.
##
## `speed_ratio` 0..1 (velocidade/teto), `throttle` -1..1.
## Parado com o pé solto: marcha lenta grave e fraca. Piso fundo: agudo e forte.
static func engine_tone(speed_ratio: float, throttle: float) -> Dictionary:
	var ratio := clampf(speed_ratio, 0.0, 1.0)
	var pedal := clampf(absf(throttle), 0.0, 1.0)
	var load := clampf(ratio * 0.7 + pedal * 0.3, 0.0, 1.0)
	var freq := lerpf(ENGINE_BASE_HZ, ENGINE_MAX_HZ, load)
	var gain := lerpf(0.045, 0.16, load)
	return {"freq": freq, "gain": gain}


func _ready() -> void:
	_engine_stream = AudioStreamGenerator.new()
	_engine_stream.mix_rate = MIX_RATE
	_engine_stream.buffer_length = 0.2
	_engine_player = AudioStreamPlayer.new()
	_engine_player.name = "Engine"
	_engine_player.stream = _engine_stream
	_engine_player.volume_db = -8.0
	add_child(_engine_player)
	_engine_player.play()

	_horn_player = AudioStreamPlayer.new()
	_horn_player.name = "Horn"
	_horn_player.stream = _horn_buffer()
	_horn_player.volume_db = -6.0
	add_child(_horn_player)


## Buzina: dois senos desafinados somados e clipados — lê como buzina sem ser
## um asset de ninguém. O buffer é pequeno (0,6 s) e gerado uma vez por carro.
static func _horn_buffer() -> AudioStreamWAV:
	var frames := int(MIX_RATE * HORN_SECONDS)
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in range(frames):
		var t := float(i) / float(MIX_RATE)
		var envelope := minf(t * 40.0, 1.0) * minf((HORN_SECONDS - t) * 40.0, 1.0)
		var sample := sin(HORN_F0 * TAU * t) * 0.5 + sin(HORN_F1 * TAU * t) * 0.35
		sample = clampf(sample * envelope, -1.0, 1.0)
		var value := int(sample * 32767.0)
		data.encode_s16(i * 2, value)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.data = data
	return wav


## Atualização por passo de física (o `Vehicle` chama).
func update_engine(speed_ratio: float, throttle: float) -> void:
	if not enabled:
		return
	var tone := VehicleAudio.engine_tone(speed_ratio, throttle)
	_target_level = float(tone["gain"])
	_engine_phase_hz = float(tone["freq"])


var _engine_phase_hz: float = ENGINE_BASE_HZ


func _process(delta: float) -> void:
	if not enabled or not is_inside_tree():
		return
	_engine_level = lerpf(_engine_level, _target_level, clampf(delta * 6.0, 0.0, 1.0))
	if _engine_playback == null:
		if _engine_player == null or not _engine_player.playing:
			return
		_engine_playback = _engine_player.get_stream_playback() as AudioStreamGeneratorPlayback
		if _engine_playback == null:
			return
	var available := _engine_playback.get_frames_available()
	if available <= 0:
		return
	var frames := mini(available, 1024)
	var increment := _engine_phase_hz / float(MIX_RATE)
	for i in range(frames):
		if not _engine_playback.can_push_frame():
			break
		_phase = fposmod(_phase + increment, 1.0)
		# Tom de motor: fundamental + segundo harmônico forte, mais um serrilhado
		# leve que lê como "máquina" e não como puro seno.
		var raw := sin(_phase * TAU) * 0.8 + sin(_phase * TAU * 2.0) * 0.3
		raw += sin(_phase * TAU * 7.0) * 0.05
		var sample := clampf(raw * _engine_level, -1.0, 1.0)
		_engine_playback.push_frame(Vector2(sample, sample))


## Buzina. `on` liga (tocando o buffer em loop até soltar), solta encerra.
func set_horn(on: bool) -> void:
	if on and not _horn_on:
		_horn_player.play()
	elif not on and _horn_on:
		_horn_player.stop()
	_horn_on = on


## Freio de mão em movimento: chiado curto reusando o buffer de buzina com o
## pitch da derrapagem ainda não modelado — PLACEHOLDER declarado.
func skid(intensity: float) -> void:
	# Sem asset de pneu: o chiado entra quando houver gravação própria. O gancho
	# existe para não mudar a API depois.
	set_horn(false)


func stop_all() -> void:
	set_horn(false)
	_target_level = 0.0


func horn_playing() -> bool:
	return _horn_on
