import json
import hashlib
import os
import uuid
from datetime import datetime

import boto3
import redis


def handler(event, context):
    try:
        body = json.loads(event.get("body") or "{}")
    except (json.JSONDecodeError, TypeError):
        return _response(400, {"error": "Invalid JSON body"})

    cache_key = hashlib.sha256(
        json.dumps(body, sort_keys=True).encode()
    ).hexdigest()

    redis_client = _get_redis()
    if redis_client:
        try:
            cached = redis_client.get(cache_key)
            if cached:
                return _response(200, json.loads(cached), x_cache="HIT")
        except Exception as e:
            print(f"Redis GET error: {e}")

    request_id = str(uuid.uuid4())
    timestamp = datetime.utcnow().isoformat() + "Z"

    result = {
        "id": request_id,
        "timestamp": timestamp,
        "cache_key": cache_key,
        "input": body,
        "processed": True,
    }

    bucket = os.environ["S3_BUCKET"]
    date_prefix = datetime.utcnow().strftime("%Y-%m-%d")
    s3_key = f"results/{date_prefix}/{request_id}.json"

    try:
        boto3.client("s3").put_object(
            Bucket=bucket,
            Key=s3_key,
            Body=json.dumps(result),
            ContentType="application/json",
        )
        result["s3_key"] = s3_key
    except Exception as e:
        print(f"S3 PutObject error: {e}")
        return _response(500, {"error": "Failed to persist result"})

    if redis_client:
        try:
            redis_client.setex(cache_key, 60, json.dumps(result))
        except Exception as e:
            print(f"Redis SET error (non-fatal): {e}")

    return _response(200, result, x_cache="MISS", x_request_id=request_id)


def _get_redis():
    host = os.environ.get("REDIS_HOST")
    port = int(os.environ.get("REDIS_PORT", "6379"))
    if not host:
        return None
    try:
        return redis.Redis(host=host, port=port, socket_connect_timeout=2, decode_responses=True)
    except Exception as e:
        print(f"Redis connect error: {e}")
        return None


def _response(status_code, body, x_cache=None, x_request_id=None):
    headers = {"Content-Type": "application/json"}
    if x_cache:
        headers["X-Cache"] = x_cache
    if x_request_id:
        headers["X-Request-Id"] = x_request_id
    return {
        "statusCode": status_code,
        "headers": headers,
        "body": json.dumps(body),
    }
