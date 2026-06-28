# Localização Robótica — Atividade 3

Pacote ROS Noetic para gravar uma trajetória do Husky no LaR simulado e gerar
mapas comparáveis com Hector SLAM e GMapping. Também é gravado uma nova bag com uma trajetoria do robô para avaliação com AMCL usando os mapas gerados individualmente com o ground truth do gazebo. 

## Configuracao do ambiente

O projeto possui um `dockerfile` para preparar o ambiente ROS/Gazebo usado nos testes. Baixe esse arquivo individualmente, coloque-o em uma pasta de trabalho e gere a imagem Docker a partir dele:

```bash
docker build -t localiza_o_robotica_ros -f dockerfile .
```

Depois que a imagem for criada, inicie o container:

```bash
docker run -it \
  --env DISPLAY=$DISPLAY \
  --env QT_X11_NO_MITSHM=1 \
  --volume /tmp/.X11-unix:/tmp/.X11-unix:rw \
  --network host \
  --name ros_lar_run \
  <sua_imagem>
```

Substitua `<sua_imagem>` pelo nome da imagem gerada no passo anterior, por exemplo `ros_lar_run`.

No host, antes de abrir interfaces graficas pelo Docker, libere o acesso ao X11:

```bash
xhost +local:docker
```

Dentro do container, clone este repositorio dentro de `~/catkin_ws/src/`:

```bash
mkdir -p ~/catkin_ws/src
cd ~/catkin_ws/src
git clone <link-do-repositorio>
```

Somente depois disso compile o workspace:

## 1. Preparação

```bash
rosrun localiza_o_robotica_at3 check_dependencies.sh --install
cd ~/catkin_ws && catkin build localiza_o_robotica_at3
source devel/setup.bash
```

## 2. Simulação e gravação

Sempre que abrir um novo terminal no container, carregue o ambiente:

```bash
docker exec -it ros_lar_run bash
export LIBGL_ALWAYS_SOFTWARE=1
source /opt/ros/noetic/setup.bash
source ~/catkin_ws/devel/setup.bash
```

Terminal 1 — inicie o LaR com o LMS1XX em `/front/scan` e sem SLAM online:

```bash
rosrun localiza_o_robotica_at3 start_simulation.sh
```

Terminal 2 — abra o controle e selecione **`/cmd_vel`**:

```bash
rosrun rqt_robot_steering rqt_robot_steering
```

Terminal 3 — grave:

```bash
rosrun localiza_o_robotica_at3 record_mapping.sh
```
No joystick gerado no Terminal 2 selecione o topico de comando do Husky, normalmente `/husky_velocity_controller/cmd_vel` ou `/cmd_vel`.
 Manipule o robo com o joystick e ao cobrir bem o laboratório, pare a gravacao no Terminal 3 com `Ctrl+C`.

## 3. Hector SLAM

Feche o Gazebo e o ROS master nos outros terminais abertos. Execute:

```bash
rosrun localiza_o_robotica_at3 generate_hector_map.sh
```

Por padrão são criados `maps/hector/lar_hector.pgm`, `lar_hector.yaml`,
`lar_hector.png` e `hector.log`.

## 4. GMapping

Depois, também sem Gazebo ou outro ROS master ativo, Execute:

```bash
rosrun localiza_o_robotica_at3 generate_gmapping_map.sh
```

Por padrão são criados `maps/gmapping/lar_gmapping.pgm`, `lar_gmapping.yaml`,
`lar_gmapping.png` e `gmapping.log`.

Ambos reproduzem a mesma bag e salvam em `/maps/` depois do replay.

## 5. Gravar uma trajetória exclusiva para localização

Com os mapas prontos, precisamos gravar o bag da trajetoria para aplicar o AMCL.

Terminal 1 — inicie o LaR com o LMS1XX em `/front/scan` e sem SLAM online:

```bash
rosrun localiza_o_robotica_at3 start_simulation.sh
```

Terminal 2 — abra o controle e selecione **`/cmd_vel`**:

```bash
rosrun rqt_robot_steering rqt_robot_steering
```

Terminal 3 — grave uma nova trajetória com:

```bash
rosrun localiza_o_robotica_at3 record_localization.sh
```

A saída padrão é `bags/lar_localization.bag`. Essa bag é criada sem SLAM e contém laser, TF, odometria e ground truth.

Faça fazer uma trajetoria pelo mapa com o Husky, pressione `Ctrl+C` quando terminar. Depois feche Gazebo e qualquer `roscore`.

## 6. Localização AMCL com o mapa Hector

Execute:

```bash
rosrun localiza_o_robotica_at3 localize_hector_map.sh
```

O mapa carregado será `maps/hector/lar_hector.yaml` e o resultado ficará em `results/localization/amcl_hector.bag`.

## 7. Localização AMCL com o mapa GMapping

Use exatamente a mesma bag de entrada:

```bash
rosrun localiza_o_robotica_at3 localize_gmapping_map.sh
```

O mapa carregado será `maps/gmapping/lar_gmapping.yaml` e o resultado ficará em `results/localization/amcl_gmapping.bag`.

## 8. Comparar AMCL com o ground truth

Depois de gerar as duas bags de localização, execute:

```bash
rosrun localiza_o_robotica_at3 compare_amcl_results.py
```

O comparador lê diretamente:

```text
results/localization/amcl_hector.bag
results/localization/amcl_gmapping.bag
```

As métricas incluem:

- erro instantâneo, médio, RMSE e erro final de posição;
- erro médio absoluto, RMSE e erro final de orientação em yaw;
- desvio padrão, percentil 95 e erro máximo;
- variação média do erro entre atualizações;
- taxa média e maior intervalo entre atualizações do AMCL;
- covariância média informada pelo AMCL.

Os resultados são gravados em `results/metrics/`:

```text
amcl_hector_metrics.csv
amcl_hector_summary.txt
amcl_gmapping_metrics.csv
amcl_gmapping_summary.txt
comparison_summary.csv
comparison_report.md
comparison_position_error.png
comparison_yaw_error.png
comparison_trajectories.png
```
## Resultados e discussao

Neste ensaio, GMapping obteve menor erro médio e RMSE de posição, mas o relatório deve ser regenerado para cada nova trajetória antes de tirar conclusões.
