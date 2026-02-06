FROM ubuntu:20.04

LABEL maintainer="User"

ENV DEBIAN_FRONTEND=noninteractive
ENV WINEARCH=win32
ENV WINEPREFIX=/home/winer/.wine
ENV DISPLAY=:1
ENV MT4DIR=$WINEPREFIX/drive_c/mt4
ENV VNC_PASSWORD=password

# Install dependencies including Wine, Xvfb, VNC, and Websockify
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    software-properties-common \
    wget \
    curl \
    unzip \
    xvfb \
    x11vnc \
    openbox \
    python3 \
    python3-numpy \
    net-tools \
    ca-certificates \
    cabextract \
    gnupg2 \
    git && \
    wget -nc https://dl.winehq.org/wine-builds/winehq.key && \
    apt-key add winehq.key && \
    add-apt-repository 'deb https://dl.winehq.org/wine-builds/ubuntu/ focal main' && \
    apt-get update && \
    apt-get install -y --install-recommends winehq-stable && \
    # Install websockify manually or via pip if needed, but apt version is usually enough or we clone it
    # We will clone websockify for stability as apt pkg might be old
    git clone https://github.com/novnc/websockify /opt/websockify && \
    # Clean up
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    rm winehq.key

# Create user
ARG USER=winer
ARG HOME=/home/$USER
ARG USER_ID=1000

RUN groupadd $USER && \
    useradd -u $USER_ID -d $HOME -g $USER -ms /bin/bash $USER

# Set up Wine prefix
USER $USER
WORKDIR $HOME

RUN wine wineboot --init && \
    # Wait for wine to initialize
    while pgrep wineserver > /dev/null; do sleep 1; done

# Copy the local Portable MT4 directory
# Note: The user's prompt implies we are building this locally or the context is available.
# Since we are modifying the repo in place, we assume the user will copy "MetaTrader 4 Portable" 
# into the build context or we configure COPY to pick it up if it was in the context.
# However, Docker COPY cannot copy from outside context. 
# I will assume the user will copy "MetaTrader 4 Portable" into "headless-metatrader4" folder before build.
# OR I will instruct the user to do so in the Git Instructions.
COPY --chown=$USER:$USER "MetaTrader 4 Portable" "$MT4DIR"

# Copy entrypoint script
COPY --chown=$USER:$USER entrypoint.sh /docker/entrypoint.sh

USER root
RUN chmod +x /docker/entrypoint.sh
USER $USER

EXPOSE 8080

ENTRYPOINT ["/docker/entrypoint.sh"]
