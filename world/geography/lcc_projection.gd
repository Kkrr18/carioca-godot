class_name CariocaProjection
extends RefCounted

## Projeção cônica conforme de Lambert (LCC) para todo o Estado do Rio de
## Janeiro, sobre o elipsoide SIRGAS 2000 / GRS80.
##
## Por que não UTM: o estado atravessa os fusos 23S e 24S. Dois fusos criam uma
## descontinuidade métrica no meio do mapa e obrigam a converter entre espaços
## quando o jogador cruza a fronteira. A LCC cobre o estado inteiro com fator
## de escala entre 0,9999 e 1,0001 (ver `scale_factor`), é invertível de forma
## analítica e mantém norte para cima em todo o território.
##
## Espaço métrico global resultante:
##   x = easting  (metros, cresce para leste)
##   y = northing (metros, cresce para norte)
## com falsa origem em (500000, 8000000) para manter tudo positivo — nenhuma
## coordenada do estado cai em quadrante negativo.
##
## Internamente as latitudes são espelhadas para o hemisfério norte (a
## formulação clássica de Snyder pressupõe cone com ápice ao norte); a API
## pública recebe e devolve latitude negativa, como nos dados de origem.

const A := 6378137.0
const INV_F := 298.257222101

const LAT_0 := -22.5
const LON_0 := -42.5
const LAT_STD_1 := -21.0
const LAT_STD_2 := -23.5
const FALSE_EASTING := 500000.0
const FALSE_NORTHING := 8000000.0

static var _initialized: bool = false
static var _e: float = 0.0
static var _e2: float = 0.0
static var _n: float = 0.0
static var _F: float = 0.0
static var _rho0: float = 0.0


static func _m(phi: float) -> float:
	var s := sin(phi)
	return cos(phi) / sqrt(1.0 - _e2 * s * s)


static func _t(phi: float) -> float:
	var s := sin(phi)
	var ratio := (1.0 - _e * s) / (1.0 + _e * s)
	return tan(PI * 0.25 - phi * 0.5) / pow(ratio, _e * 0.5)


static func _initialize() -> void:
	if _initialized:
		return
	var f := 1.0 / INV_F
	var e2 := f * (2.0 - f)
	var e := sqrt(e2)
	var phi1 := deg_to_rad(-LAT_STD_1)
	var phi2 := deg_to_rad(-LAT_STD_2)
	var phi0 := deg_to_rad(-LAT_0)
	var m1 := _m_with(phi1, e2)
	var m2 := _m_with(phi2, e2)
	var t1 := _t_with(phi1, e)
	var t2 := _t_with(phi2, e)
	var t0 := _t_with(phi0, e)
	var n := (log(m1) - log(m2)) / (log(t1) - log(t2))
	var capital_f := m1 / (n * pow(t1, n))
	# Só publica os valores depois de calculados: o carregador de setores usa
	# esta projeção em outra thread, e um flag marcado cedo poderia entregar
	# constantes pela metade.
	_e2 = e2
	_e = e
	_n = n
	_F = capital_f
	_rho0 = A * capital_f * pow(t0, n)
	_initialized = true


static func _m_with(phi: float, e2: float) -> float:
	var s := sin(phi)
	return cos(phi) / sqrt(1.0 - e2 * s * s)


static func _t_with(phi: float, e: float) -> float:
	var s := sin(phi)
	var ratio := (1.0 - e * s) / (1.0 + e * s)
	return tan(PI * 0.25 - phi * 0.5) / pow(ratio, e * 0.5)


## Latitude negativa (sul), longitude negativa (oeste) -> metros (easting, northing).
static func forward(latitude: float, longitude: float) -> Vector2:
	_initialize()
	var phi := deg_to_rad(-latitude)
	var lam := deg_to_rad(longitude)
	var rho := A * _F * pow(_t(phi), _n)
	var theta := _n * (lam - deg_to_rad(LON_0))
	var x := rho * sin(theta)
	var y_mirror := _rho0 - rho * cos(theta)
	return Vector2(FALSE_EASTING + x, FALSE_NORTHING - y_mirror)


## Metros (easting, northing) -> Vector2(latitude, longitude).
static func inverse(easting: float, northing: float) -> Vector2:
	_initialize()
	var x := easting - FALSE_EASTING
	var y_mirror := FALSE_NORTHING - northing
	var dy := _rho0 - y_mirror
	var rho := sqrt(x * x + dy * dy)
	if rho <= 0.0:
		return Vector2(LAT_0, LON_0)
	var theta := atan2(x, dy)
	var t := pow(rho / (A * _F), 1.0 / _n)
	var phi := PI * 0.5 - 2.0 * atan(t)
	for _iteration in range(6):
		var s := sin(phi)
		var ratio := (1.0 - _e * s) / (1.0 + _e * s)
		phi = PI * 0.5 - 2.0 * atan(t * pow(ratio, _e * 0.5))
	var lam := deg_to_rad(LON_0) + theta / _n
	return Vector2(-rad_to_deg(phi), rad_to_deg(lam))


## Fator de escala pontual da projeção. Vale exatamente 1 nos paralelos padrão;
## é o número que prova que a projeção não deforma distâncias no estado.
static func scale_factor(latitude: float) -> float:
	_initialize()
	var phi := deg_to_rad(-latitude)
	var rho := A * _F * pow(_t(phi), _n)
	return (_n * rho) / (A * _m(phi))


## Constante de cone, exposta para diagnóstico.
static func cone_constant() -> float:
	_initialize()
	return _n
