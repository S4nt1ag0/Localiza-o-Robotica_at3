# Localização Robótica — Atividade 3

Pacote ROS Noetic para gravar uma trajetória do Husky no LaR simulado e gerar
mapas comparáveis com Hector SLAM e GMapping. A bag também preserva odometria,
IMU e ground truth para a futura avaliação com AMCL.

## 1. Preparação

```bash
cd ~/catkin_ws
source /opt/ros/noetic/setup.bash
catkin build localiza_o_robotica_at3
source devel/setup.bash
rosrun localiza_o_robotica_at3 check_dependencies.sh
```

Se houver dependências ausentes, instale-as explicitamente e recompile:

```bash
rosrun localiza_o_robotica_at3 check_dependencies.sh --install
cd ~/catkin_ws && catkin build localiza_o_robotica_at3
source devel/setup.bash
```

## 2. Simulação e gravação

Use três terminais com `/opt/ros/noetic/setup.bash` e
`~/catkin_ws/devel/setup.bash` carregados.

Terminal 1 — inicie o LaR com o LMS1XX em `/front/scan` e sem SLAM online:

```bash
rosrun localiza_o_robotica_at3 start_simulation.sh
```

Terminal 2 — abra o controle e selecione **`/cmd_vel`**:

```bash
rosrun rqt_robot_steering rqt_robot_steering
```

Comece com velocidades baixas, como `0,4 m/s` e `0,5 rad/s`. Faça curvas
suaves, observe paredes de ângulos diferentes e revisite áreas já percorridas.

Terminal 3 — grave:

```bash
rosrun localiza_o_robotica_at3 record_mapping.sh
```

 Ao cobrir bem o laboratório, pressione `Ctrl+C`
somente no terminal da gravação para o rosbag fechar e indexar o arquivo.

## 3. Hector SLAM

Feche o Gazebo e o ROS master da simulação. Execute:

```bash
rosrun localiza_o_robotica_at3 generate_hector_map.sh
```

Por padrão são criados `maps/hector/lar_hector.pgm`, `lar_hector.yaml`,
`lar_hector.png` e `hector.log`.

## 4. GMapping

Também sem Gazebo ou outro ROS master ativo:

```bash
rosrun localiza_o_robotica_at3 generate_gmapping_map.sh
```

Por padrão são criados `maps/gmapping/lar_gmapping.pgm`, `lar_gmapping.yaml`,
`lar_gmapping.png` e `gmapping.log`.

Ambos reproduzem integralmente a mesma bag com `/use_sim_time`, resolução de
`0,05 m`, e salvam por `/dynamic_map` depois do replay. Não rode os dois juntos.

## 5. Gravar uma trajetória exclusiva para localização

Inicie novamente o Gazebo e o steering como na seção 2. Em outro terminal,
grave uma nova trajetória:

```bash
rosrun localiza_o_robotica_at3 record_localization.sh
```

A saída padrão é `bags/lar_localization.bag`. O script não permite usar o
caminho de `lar_mapping.bag` e também não sobrescreve uma gravação existente.
Essa bag é criada sem SLAM e contém laser, TF, odometria e ground truth.

Ao dirigir, comece na pose padrão do Husky, faça uma trajetória representativa
e pressione `Ctrl+C` quando terminar. Depois feche Gazebo e qualquer `roscore`.

## 6. Localização AMCL com o mapa Hector

Execute:

```bash
rosrun localiza_o_robotica_at3 localize_hector_map.sh
```

O comando executa, nesta ordem:

1. carrega `maps/hector/lar_hector.yaml`;
2. inicia AMCL na pose `(0, 0, 0)`;
3. inicia a gravação do resultado;
4. reproduz integralmente `bags/lar_localization.bag`.

O resultado fica em `results/localization/amcl_hector.bag`.

## 7. Localização AMCL com o mapa GMapping

Use exatamente a mesma bag de entrada:

```bash
rosrun localiza_o_robotica_at3 localize_gmapping_map.sh
```

O mapa carregado será `maps/gmapping/lar_gmapping.yaml` e o resultado ficará em
`results/localization/amcl_gmapping.bag`.

As bags de resultado não são sobrescritas.

Com a posição inicial padrão do simulador e dos mapas gerados neste projeto,
use `(0, 0, 0)`. Os resultados preservam `/amcl_pose`, `/particlecloud`, TF,
odometria e `/gazebo_ground_truth/odom`, permitindo calcular posteriormente
erro de posição, RMSE, erro angular e estabilidade sem repetir o AMCL.
