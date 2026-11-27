class_name PlatformProfile
extends RefCounted

## Detecção de plataforma e escolha do perfil gráfico inicial.
## O mesmo mundo roda em PC e em iPhone 12; o que muda é o perfil aplicado.


static func is_mobile() -> bool:
	return OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()


static func adapter_name() -> String:
	return RenderingServer.get_video_adapter_name()


static func recommended_preset() -> String:
	if is_mobile():
		return "mobile"
	var adapter := adapter_name().to_lower()
	for needle in ["rtx", "radeon rx", "apple m", "arc a", "gtx 16", "gtx 20"]:
		if adapter.contains(needle):
			return "pc_high"
	return "pc_medium"


static func summary() -> Dictionary:
	return {
		"os": OS.get_name(),
		"adapter": adapter_name(),
		"cores": OS.get_processor_count(),
		"touchscreen": DisplayServer.is_touchscreen_available(),
		"mobile": is_mobile(),
		"recommended_preset": recommended_preset(),
	}
