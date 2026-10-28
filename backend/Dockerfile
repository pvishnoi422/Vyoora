# Build with: docker build -t vyoora backend
FROM python:3.11-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1
WORKDIR /app
COPY requirements.lock .
RUN pip install -r requirements.lock && useradd --uid 10001 --create-home appuser
COPY app.py contracts.py provider.py safety.py gunicorn.conf.py ./
USER appuser
EXPOSE 8080
CMD ["gunicorn", "--config", "gunicorn.conf.py", "app:app"]
