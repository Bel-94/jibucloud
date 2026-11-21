import json
import logging
from urllib.parse import unquote_plus

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def lambda_handler(event, context):
    """
    SQS invokes this function with one or more SQS records.
    Each SQS record body contains the EventBridge S3 event as JSON.
    """
    failures = []

    for record in event.get("Records", []):
        message_id = record.get("messageId", "unknown")

        try:
            eventbridge_event = json.loads(record["body"])
            detail = eventbridge_event.get("detail", {})

            bucket_name = detail.get("bucket", {}).get("name", "unknown")
            object_key = unquote_plus(
                detail.get("object", {}).get("key", "unknown")
            )
            event_time = eventbridge_event.get("time", "unknown")
            event_name = eventbridge_event.get("detail-type", "unknown")

            submission = {
                "message": "JibuCloud received a new assignment submission",
                "event_name": event_name,
                "bucket": bucket_name,
                "object_key": object_key,
                "event_time": event_time,
            }

            # One structured log line makes the result easy to find in CloudWatch.
            logger.info(json.dumps(submission))

        except (KeyError, TypeError, json.JSONDecodeError) as exc:
            logger.exception(
                "Could not process SQS message %s: %s", message_id, exc
            )
            # Tell the SQS event source mapping to retry this message.
            failures.append({"itemIdentifier": message_id})

    return {"batchItemFailures": failures}
