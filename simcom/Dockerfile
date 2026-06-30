FROM python:3-slim

RUN pip install --root-user-action=ignore paho-mqtt dbus-next

WORKDIR /app

ENTRYPOINT [ "python3", "-u", "./main.py" ]