class_name Deterministic
extends RefCounted

## Aleatoriedade determinística.
##
## Tudo que é gerado por procedimento (relevo, ruas, lotes, vegetação) precisa
## dar exatamente o mesmo resultado em qualquer sessão, em qualquer plataforma
## e em qualquer ordem de carregamento de setor. Por isso não existe `randf()`:
## cada valor vem de um hash dos índices inteiros que identificam aquilo no
## mundo. Dois setores vizinhos que consultam o mesmo nó da rede de ruas
## chegam ao mesmo ponto — sem estado compartilhado.

const MASK := 0x7FFFFFFF


static func hash2(a: int, b: int, salt: int = 0) -> int:
	var h: int = a * 374761393 + b * 668265263 + salt * 1013904223 + 1442695041
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return h & MASK


static func hash3(a: int, b: int, c: int, salt: int = 0) -> int:
	return hash2(a * 7919 + c * 104729, b, salt)


static func rand01(a: int, b: int, salt: int = 0) -> float:
	return float(hash2(a, b, salt)) / float(MASK)


static func rand01_3(a: int, b: int, c: int, salt: int = 0) -> float:
	return float(hash3(a, b, c, salt)) / float(MASK)


static func rand_signed(a: int, b: int, salt: int = 0) -> float:
	return rand01(a, b, salt) * 2.0 - 1.0


static func rand_range(a: int, b: int, low: float, high: float, salt: int = 0) -> float:
	return lerpf(low, high, rand01(a, b, salt))


## Ruído de valor contínuo em [-1, 1]. Contínuo porque interpola com curva
## suave entre nós inteiros — é o que evita degraus no terreno.
static func value_noise(x: float, y: float, salt: int = 0) -> float:
	var xi := floori(x)
	var yi := floori(y)
	var fx := x - float(xi)
	var fy := y - float(yi)
	var sx := fx * fx * (3.0 - 2.0 * fx)
	var sy := fy * fy * (3.0 - 2.0 * fy)
	var n00 := rand01(xi, yi, salt)
	var n10 := rand01(xi + 1, yi, salt)
	var n01 := rand01(xi, yi + 1, salt)
	var n11 := rand01(xi + 1, yi + 1, salt)
	var a := lerpf(n00, n10, sx)
	var b := lerpf(n01, n11, sx)
	return lerpf(a, b, sy) * 2.0 - 1.0


static func fbm(x: float, y: float, octaves: int, salt: int = 0) -> float:
	var total := 0.0
	var amplitude := 0.5
	var frequency := 1.0
	var norm := 0.0
	for i in range(maxi(octaves, 1)):
		total += value_noise(x * frequency, y * frequency, salt + i * 101) * amplitude
		norm += amplitude
		amplitude *= 0.5
		frequency *= 2.0
	if norm <= 0.0:
		return 0.0
	return total / norm


## Chave textual estável para nós de rede (usada para conectar vias de setores
## vizinhos sem depender de igualdade exata de float entre arquivos).
static func node_key(prefix: String, a: int, b: int) -> String:
	return "%s:%d:%d" % [prefix, a, b]
