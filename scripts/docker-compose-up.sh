docker compose down -v
docker compose build --no-cache
docker compose up -d

docker ps


echo "=========================================="
echo "🌐 Airflow UI  : http://localhost:8080"
echo "📡 Kafka       : localhost:9092"
echo "⚡ Spark(local): docker internal local setup"
echo "=========================================="