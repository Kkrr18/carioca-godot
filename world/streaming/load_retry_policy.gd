class_name LoadRetryPolicy
extends RefCounted

## Política de retentativa de carga de setor.
##
## Falha de carga tem duas formas e as duas precisam de resposta diferente:
##
## - **Falha transitória** (arquivo sendo escrito, disco ocupado, tarefa que
##   travou e foi abandonada pelo watchdog): vale tentar de novo, com espera
##   crescente — repetir imediatamente só queima thread.
## - **Falha persistente** (JSON corrompido, schema incompatível, permissão):
##   insistar não resolve e enche o log a 30 FPS. Depois do teto de tentativas o
##   setor fica de quarentena por um tempo longo antes de valer nova tentativa.
##
## A espera cresce linearmente com a tentativa: 1×, 2×, 3× a base. Não é
## exponencial de propósito — o mundo deve se recuperar em segundos, não em
## minutos, quando o problema é passageiro.

var max_attempts: int = 3
var base_delay_s: float = 1.5
var quarantine_s: float = 60.0


func delay_for(attempts: int) -> float:
	if attempts <= 0:
		return 0.0
	return base_delay_s * float(attempts)


func can_retry(attempts: int) -> bool:
	return attempts <= max_attempts


## Espera a aplicar depois da tentativa de número `attempts` (1 = primeira
## falha). Retorna em milissegundos porque é assim que o manager mede tempo.
func delay_msec_for(attempts: int) -> int:
	if attempts <= 0:
		return 0
	if can_retry(attempts):
		return int(round(delay_for(attempts) * 1000.0))
	return int(round(quarantine_s * 1000.0))
