FROM python:3.11-slim

WORKDIR /opt/project

COPY ./src/app /opt/project/app
COPY requirements.txt /opt/project/requirements.txt

RUN pip install --upgrade pip && \
    pip install --no-cache-dir -r /opt/project/requirements.txt

ENV PYTHONPATH=/opt/project/app

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
