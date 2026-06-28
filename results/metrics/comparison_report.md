# Comparação AMCL: Hector SLAM vs GMapping

| Método | Erro médio (m) | RMSE posição (m) | Erro final (m) | RMSE yaw (rad) | Desvio erro pos. (m) | P95 erro pos. (m) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| hector | 0.250224 | 0.278254 | 0.190349 | 0.018122 | 0.121711 | 0.418044 |
| gmapping | 0.217926 | 0.252217 | 0.101475 | 0.019441 | 0.126971 | 0.406654 |

A estabilidade é representada principalmente pelo desvio padrão, P95 e máximo do erro, pela variação média entre atualizações e pelo maior intervalo sem atualização.
