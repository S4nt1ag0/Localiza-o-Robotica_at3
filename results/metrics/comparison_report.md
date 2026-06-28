# Comparação AMCL: Hector SLAM vs GMapping

| Método | Erro médio (m) | RMSE posição (m) | Erro final (m) | RMSE yaw (rad) | Desvio erro pos. (m) | P95 erro pos. (m) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| hector | 0.286809 | 0.318807 | 0.392276 | 0.020653 | 0.139207 | 0.442440 |
| gmapping | 0.145000 | 0.176814 | 0.031099 | 0.015285 | 0.101184 | 0.305774 |

A estabilidade é representada principalmente pelo desvio padrão, P95 e máximo do erro, pela variação média entre atualizações e pelo maior intervalo sem atualização.
