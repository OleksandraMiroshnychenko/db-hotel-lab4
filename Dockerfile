FROM python:3.9-buster

WORKDIR /code

ENV PYTHONDONTWRITEBYTECODE 1
ENV PYTHONUNBUFFERED 1

# install python modules
RUN pip install --upgrade pip
COPY ./requirements.txt .
RUN python3 -m pip install -r requirements.txt --no-cache-dir

# copy project tree
COPY ./lab3 .

#CMD ["python", "cli.py"]
