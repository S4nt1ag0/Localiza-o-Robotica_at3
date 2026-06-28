# Use a imagem base do Ubuntu 20.04 LTS
FROM ubuntu:20.04
SHELL ["/bin/bash", "-c"]

# Define algumas variáveis de ambiente para o Brasil (pt_BR)
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=pt_BR.UTF-8 \
    LC_ALL=pt_BR.UTF-8

# Atualiza a lista de pacotes e instala pacotes básicos
USER root
RUN apt-get update && apt-get update -y &&\
    apt-get install -y \
    apt-utils \
    locales \
    sudo \
    software-properties-common \
    wget \
    curl \
    git \
    vim \
    nano \
    net-tools \
    dbus \
    dbus-x11 \
    x11-utils \
    mesa-utils \
    mesa-utils-extra \
    libgl1-mesa-dri \
    libgl1-mesa-glx \
    mesa-utils-extra \
    mesa-utils \
    mesa-utils-extra \
    mesa-utils-extra

# Configuração do ambiente X11 forwarding
RUN echo "allowed_users=anybody" > /etc/X11/Xwrapper.config

# Configuração de localidade para o Brasil (pt_BR)
RUN locale-gen pt_BR.UTF-8

# Adiciona um usuário não-root chamado "ros" com senha "rosdocker"
RUN useradd -m -s /bin/bash ros && \
    echo "ros:rosdocker" | chpasswd && \
    adduser ros sudo

# Define o usuário padrão ao iniciar o container
USER ros

# Diretório de trabalho padrão
WORKDIR /home/ros

# Instalação do ROS Noetic
USER root
RUN sudo apt-get update \
    && sudo sh -c 'echo "deb http://packages.ros.org/ros/ubuntu $(lsb_release -sc) main" > /etc/apt/sources.list.d/ros-latest.list' \
    && sudo apt install -y curl \
    && curl -s https://raw.githubusercontent.com/ros/rosdistro/master/ros.asc | sudo apt-key add - \
    && sudo apt-get update \
    && echo "keyboard-configuration keyboard-configuration/layout select 'English (US)'" | debconf-set-selections \
    && echo "keyboard-configuration keyboard-configuration/variant select 'English (US) - English (US, intl., with dead keys)'" | debconf-set-selections \
    && sudo apt-get install -y ros-noetic-desktop-full


# Configuração do ambiente ROS
RUN echo "source /opt/ros/noetic/setup.bash" >> ~/.bashrc \
    && source ~/.bashrc

# Instalação das dependencias ROS Noetic

RUN sudo apt-get install -y python3-rosdep python3-rosinstall python3-rosinstall-generator python3-wstool build-essential

# Inicializa rosdep
RUN sudo rosdep init \
    && rosdep update

WORKDIR /home/ros

RUN sudo apt-get update && \
    sudo apt-get install -y ninja-build \
        exiftool \
        protobuf-compiler \
        libeigen3-dev \
        genromfs \
        xmlstarlet \
        python3-pip \
        gawk

RUN pip3 install py3rosmsgs \
        packaging \
        numpy \
        empy \
        toml \
        pyyaml \
        jinja2 \
        pyargparse \
        kconfiglib \
        jsonschema \
        future \
        pandas \
        jinja2 \
        pyserial \
        cerberus \
        pyulog==0.7.0 \
        pyquaternion

RUN sudo apt-get install -y libgstreamer1.0-dev \
        libgstreamer-plugins-base1.0-dev \
        libgstreamer-plugins-bad1.0-dev \
        gstreamer1.0-plugins-base \
        gstreamer1.0-plugins-good \
        gstreamer1.0-plugins-bad \
        gstreamer1.0-plugins-ugly \
        gstreamer1.0-libav \
        gstreamer1.0-doc \
        gstreamer1.0-tools \
        gstreamer1.0-x \
        gstreamer1.0-alsa \
        gstreamer1.0-gl \
        gstreamer1.0-gtk3 \
        gstreamer1.0-qt5 \
        gstreamer1.0-pulseaudio

RUN sudo apt-get remove -y gazebo* \
        libgazebo* \
        ros-noetic-gazebo* \
    && sudo apt-get clean \
    && sudo rm -rf /var/lib/apt/lists/*

RUN sudo apt-get update \
    && sudo apt-get install -y \
        gazebo11 \
        libgazebo11-dev \
        ros-noetic-gazebo-ros \
        ros-noetic-gazebo-ros-pkgs \
        ros-noetic-gazebo-ros-control \
    && sudo rm -rf /var/lib/apt/lists/*

RUN sudo apt-get update \
    && sudo apt-get install -y ros-noetic-moveit-msgs \
        ros-noetic-object-recognition-msgs \
        ros-noetic-octomap-msgs \
        ros-noetic-camera-info-manager \
        ros-noetic-control-toolbox \
        ros-noetic-polled-camera \
        ros-noetic-effort-controllers \
        ros-noetic-joint-state-controller \
        ros-noetic-position-controllers \
        ros-noetic-velocity-controllers \
        ros-noetic-mavros \
        ros-noetic-mavros-extras \
        build-essential \
        python3-rosdep \
        python3-catkin-tools \
        libusb-dev \
        python3-osrf-pycommon \
        libspnav-dev \
        libbluetooth-dev \
        libcwiid-dev \
        libgoogle-glog-dev \
    && sudo rm -rf /var/lib/apt/lists/*

#RUN wget "qualquer git"

USER ros

RUN mkdir -p ~/catkin_ws/src &&\
    mkdir -p ~/catkin_ws/scripts &&\
    cd ~/catkin_ws/src &&\
    source /opt/ros/noetic/setup.sh &&\
    catkin_init_workspace &&\
    git clone -b noetic https://github.com/lar-deeufba/lar_gazebo.git &&\
    cd ~/catkin_ws &&\
    rosdep update &&\
    rosdep install --from-paths src/lar_gazebo --ignore-src -r -y --rosdistro noetic || true &&\
    catkin build

RUN echo "source ~/catkin_ws/devel/setup.bash" >> ~/.bashrc \
    && source ~/.bashrc

RUN mkdir .gazebo &&\
    cd ~/.gazebo &&\
    git clone https://github.com/osrf/gazebo_models.git &&\
    mv gazebo_models models

RUN cd ~/.gazebo/models/ &&\
    rm -r stereo_camera/

USER root

# Atualize a lista de pacotes e instale o VSCode
#RUN apt-get update && \
#    apt-get install -y \
#    code

USER ros

RUN source ~/catkin_ws/devel/setup.bash

# Comando de entrada padrão (se desejado, pode ser substituído ao executar o contêiner)
CMD ["/bin/bash"]
