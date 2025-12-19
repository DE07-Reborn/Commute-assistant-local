FROM python:3.11-slim

WORKDIR /opt/project

COPY requirements.txt /opt/project/requirements.txt

RUN pip install --upgrade pip && \
    pip install --no-cache-dir -r /opt/project/requirements.txt

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]