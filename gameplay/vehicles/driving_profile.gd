class_name DrivingProfile
extends RefCounted

## Números do veículo, num lugar só — o mesmo padrão do `MovementProfile`.
##
## Antes da Etapa 5 as forças viviam como constantes dentro de `Vehicle` (o que
## já era um passo à frente das Etapas 1–3, mas ainda sem caminho de preset).
## Agora o perfil é um objeto: o `DriveModel` consome um perfil, trocar de
## perfil não muda uma linha de lógica, e o teste exercita "sprint é mais
## rápido" — aqui, "civic acelera mais que caminhão" — sem corpo físico.
##
## A dirigibilidade alvo é a de GTA V: arcade-realista. Isto NÃO é um
## simulador: não há câmbio simulado, diferencial, transferência de peso por
## física de massa — a transferência de peso é a que o VehicleBody3D nativo
## produz sozinho com o centro de massa e a suspensão.

const GEAR_DRIVE := 1
const GEAR_REVERSE := -1

## Motor. `engine_force` é força no VehicleBody3D (N·? na prática, número do
## motor da Godot). A aceleração progressiva vem da redução da força perto da
## velocidade máxima, e a resistência do ar vem do `linear_damp` do corpo.
var engine_force: float = 1600.0
var max_speed: float = 33.0           # m/s (~119 km/h)
var reverse_factor: float = 0.45      # força da ré relativa à frente
var max_reverse_speed: float = 9.0    # m/s — a ré tem teto próprio

## Freio. `brake_force` no VehicleWheel3D é por roda (m²·kg/s² do servidor).
var brake_force: float = 12.0
var handbrake_force: float = 24.0
## Fração da aderência das rodas traseiras com o freio de mão: é isto que
## permite derrapar. 1.0 = sem efeito; 0.35 = traseira quase solta.
var handbrake_grip: float = 0.35
## Freio de motor quando ninguém pisa em pedal nenhum (m/s² aplicado como freio).
var coast_brake: float = 3.0

## Direção. O esterço disponível cai com a velocidade — é o que separa
## "arcade-realista" de "gelo": em 60 km/h o volante vira menos que parado.
var max_steer: float = 0.52           # rad (~30°)
var steer_rate: float = 2.8           # rad/s com input
var steer_return_rate: float = 3.4    # rad/s soltando o volante
var steer_falloff_speed: float = 26.0 # m/s em que o esterço já está no mínimo
var min_steer_factor: float = 0.32    # fração do esterço em alta velocidade

## Aderência e tração. A chuva interpola para `grip_wet` (`apply_wetness`).
var grip_dry: float = 3.0
var grip_wet: float = 1.35
## "rwd" | "fwd" | "awd" — quais rodas recebem tração (ordem: 0,1 frente).
var traction_mode: String = "rwd"

## Corpo. Massa, centro de massa e amortecimento são do VehicleBody3D.
var mass: float = 1250.0
var center_of_mass_height: float = 0.35
var linear_damp: float = 0.35         # resistência do ar (o resto da curva é do motor)


static func from_preset(preset: Dictionary) -> DrivingProfile:
	var profile := DrivingProfile.new()
	profile.engine_force = maxf(float(preset.get("vehicle_engine_force", profile.engine_force)), 200.0)
	profile.max_speed = clampf(float(preset.get("vehicle_max_speed", profile.max_speed)), 5.0, 70.0)
	profile.brake_force = clampf(float(preset.get("vehicle_brake_force", profile.brake_force)), 2.0, 40.0)
	profile.max_steer = clampf(float(preset.get("vehicle_max_steer", profile.max_steer)), 0.15, 0.9)
	profile.grip_dry = clampf(float(preset.get("vehicle_grip", profile.grip_dry)), 0.5, 8.0)
	return profile


func grip_for(wetness: float) -> float:
	return lerpf(grip_dry, grip_wet, clampf(wetness, 0.0, 1.0))


## Fração do esterço disponível nesta velocidade. Cai de 1.0 parado até
## `min_steer_factor` a partir de `steer_falloff_speed`.
func steer_factor(speed: float) -> float:
	var ratio := clampf(absf(speed) / steer_falloff_speed, 0.0, 1.0)
	return lerpf(1.0, min_steer_factor, ratio)


func describe() -> String:
	return "motor %.0f · teto %.0f km/h · freio %.1f · esterço %.0f° · aderência %.1f · tração %s" % [
		engine_force,
		max_speed * 3.6,
		brake_force,
		rad_to_deg(max_steer),
		grip_dry,
		traction_mode,
	]
