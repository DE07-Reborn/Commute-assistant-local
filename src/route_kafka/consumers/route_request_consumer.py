import json
import logging
import sys
from datetime import datetime
from zoneinfo import ZoneInfo

from kafka import KafkaConsumer
from route_kafka.utils.feedback import calculate_depart_at, adjust_route_for_display

KST = ZoneInfo("Asia/Seoul")
logger = logging.getLogger(__name__)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s - %(message)s",
    stream=sys.stdout,
)

class RouteKafkaConsumer:
    def __init__(
        self,
        bootstrap_servers: str,
        redis_repo,
        route_service,
        topic: str = "route_request",
        group_id: str = "route-worker",
    ):
        self.redis = redis_repo
        self.route_service = route_service

        self.consumer = KafkaConsumer(
            topic,
            bootstrap_servers=bootstrap_servers,
            group_id=group_id,
            enable_auto_commit=False,
            auto_offset_reset="latest",
            value_deserializer=lambda v: json.loads(v.decode("utf-8")),
        )

    def start(self):
        """
            Initiate consumer
            Read message from topic
        """
        logger.info('[INIT] Route Kafka consumer started')

        for msg in self.consumer:
            try:
                self.handle_message(msg.value)
                self.consumer.commit()
            except Exception:
                logger.exception('[ERROR] Failed to process message')
                continue


    def skipper(self, now, arrive_by, redis_cache):
        """
            Check whether current user has enough time to go work address
            Or Skip if user is already on his way
            param
                now : Current time 
                arrive_by : User's arrive time at work address
                redis_cache : Cache data in redis
        """
        remaining_sec = (arrive_by - now).total_seconds()
        if remaining_sec <= 0:
            return True
        
        cached_duration = redis_cache.get('total_duration_sec')
        try:
            total_duration_sec = int(cached_duration) if cached_duration is not None else 0
        except (TypeError, ValueError):
            total_duration_sec = 0
        return remaining_sec < total_duration_sec
    

    def handle_message(self, message):
        """
            Handle each topic meassage
            1. Check redis cache to see whether the route is already exists and still meaningful
            2. Request Google route API 
            3. Calculate depart time
            4. Adjust route by feedback
            5. set into redis
            param
                message : topic message
        """
        user_id = message['user_id']
        arrive_by = datetime.fromisoformat(message['arrive_by'])
        if arrive_by.tzinfo is None:
            arrive_by = arrive_by.replace(tzinfo=KST)
        feedback_sec = message.get("feedback_time_sec", 0)
        feedback_min = feedback_sec // 60
        now = datetime.now(KST)

        redis_cache = self.redis.get(user_id)

        if redis_cache and self.skipper(now, arrive_by, redis_cache):
            logger.debug(
                    f'[SKIP] Insufficient Time Or Already on going'
                    f"user_id={user_id} now={now.isoformat()} arrive_by={arrive_by.isoformat()} "
                    f"cached_total={redis_cache.get('total_duration_sec')} feedback_min={redis_cache.get('feedback_min', 0)}"
            )
            return
        
        route = self.route_service.fetch_route(message)

        depart_at = calculate_depart_at(
            arrive_by,
            route['total_duration_sec'],
            feedback_min
        )
        route["total_duration_sec"] += feedback_sec
        
        route = adjust_route_for_display(route, feedback_min)

        payload = {
            "user_id": user_id,
            "depart_at": depart_at.isoformat(),
            "arrive_by": arrive_by.isoformat(),
            "total_duration_sec": route["total_duration_sec"],
            "feedback_min": feedback_min,
            "route": route,
            "generated_at": datetime.now(KST).isoformat(),
        }

        self.redis.set(user_id, payload)

        logger.info(
            f"[DONE] route cached user_id={user_id} "
            f"depart_at={payload['depart_at']}"
        )